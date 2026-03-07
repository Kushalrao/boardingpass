/**
 * PDF Service — Handles encryption detection, password decryption,
 * and preparation of PDF buffers for Claude API processing.
 *
 * Uses MuPDF (WASM) for reliable encryption handling across all
 * PDF encryption methods (RC4, AES-128, AES-256).
 */

// mupdf is ESM-only — must use dynamic import
let mupdfModule: typeof import('mupdf') | null = null;

async function getMupdf() {
  if (!mupdfModule) {
    mupdfModule = await import('mupdf');
  }
  return mupdfModule;
}

export interface PdfResult {
  /** Decrypted PDF buffer ready to send to Claude */
  pdfBuffer: Buffer;
  /** Whether the PDF was password-protected */
  wasEncrypted: boolean;
  /** The password that worked (null if not encrypted) */
  passwordUsed: string | null;
  /** Number of pages in the PDF */
  pageCount: number;
}

export type PdfFailureReason = 'password_required' | 'corrupt' | 'empty' | 'unknown';

export class PdfService {
  /**
   * Check if a PDF buffer is password-protected.
   */
  async isEncrypted(buffer: Buffer): Promise<boolean> {
    const mupdf = await getMupdf();
    try {
      const doc = mupdf.Document.openDocument(buffer, 'application/pdf');
      const needsPwd = doc.needsPassword();
      return needsPwd;
    } catch {
      // If we can't even open it, it might be corrupt
      return false;
    }
  }

  /**
   * Open a PDF, decrypt if needed, and return a clean buffer.
   *
   * Flow:
   *  1. Open the PDF with mupdf
   *  2. If not encrypted → return buffer as-is with metadata
   *  3. If encrypted → try each password candidate
   *  4. If a password works → save decrypted version without encryption
   *  5. If no password works → throw with reason 'password_required'
   *
   * @param buffer    Raw PDF bytes from Gmail
   * @param passwords Ordered list of password candidates to try
   * @returns PdfResult with decrypted buffer and metadata
   * @throws Error with message containing the PdfFailureReason
   */
  async processForClaude(
    buffer: Buffer,
    passwords: string[]
  ): Promise<PdfResult> {
    const mupdf = await getMupdf();

    let doc;
    try {
      doc = mupdf.Document.openDocument(buffer, 'application/pdf');
    } catch (e: any) {
      throw new Error(`corrupt: Could not open PDF — ${e?.message || e}`);
    }

    // Check if password is needed
    if (!doc.needsPassword()) {
      // Not encrypted — return original buffer
      const pageCount = doc.countPages();
      if (pageCount === 0) {
        throw new Error('empty: PDF has 0 pages');
      }
      return {
        pdfBuffer: buffer,
        wasEncrypted: false,
        passwordUsed: null,
        pageCount,
      };
    }

    // PDF is encrypted — try passwords
    let passwordUsed: string | null = null;

    for (const pwd of passwords) {
      if (doc.authenticatePassword(pwd)) {
        passwordUsed = pwd;
        break;
      }
    }

    if (!passwordUsed) {
      throw new Error(
        'password_required: PDF is password-protected and none of the candidate passwords worked'
      );
    }

    // Password worked — save a decrypted copy
    const pageCount = doc.countPages();
    if (pageCount === 0) {
      throw new Error('empty: PDF has 0 pages after decryption');
    }

    // Convert to PDFDocument to use saveToBuffer
    if (doc.isPDF()) {
      const pdfDoc = doc.asPDF();
      try {
        // saveToBuffer returns the PDF without encryption
        const decryptedData = pdfDoc.saveToBuffer('compress');
        const decryptedBuffer = Buffer.from(
          decryptedData.buffer,
          decryptedData.byteOffset,
          decryptedData.byteLength
        );

        return {
          pdfBuffer: decryptedBuffer,
          wasEncrypted: true,
          passwordUsed,
          pageCount,
        };
      } catch (saveErr: any) {
        // If saveToBuffer fails, return original buffer
        // (Claude might still be able to read it since password was authenticated)
        console.warn('Could not save decrypted PDF, returning original buffer:', saveErr?.message);
        return {
          pdfBuffer: buffer,
          wasEncrypted: true,
          passwordUsed,
          pageCount,
        };
      }
    }

    // Shouldn't reach here for PDFs, but fallback
    return {
      pdfBuffer: buffer,
      wasEncrypted: true,
      passwordUsed,
      pageCount,
    };
  }
}
