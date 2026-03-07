"use strict";
/**
 * PDF Service — Handles encryption detection, password decryption,
 * and preparation of PDF buffers for Claude API processing.
 *
 * Uses MuPDF (WASM) for reliable encryption handling across all
 * PDF encryption methods (RC4, AES-128, AES-256).
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.PdfService = void 0;
// mupdf is ESM-only — must use dynamic import
let mupdfModule = null;
async function getMupdf() {
    if (!mupdfModule) {
        mupdfModule = await Promise.resolve().then(() => __importStar(require('mupdf')));
    }
    return mupdfModule;
}
class PdfService {
    /**
     * Check if a PDF buffer is password-protected.
     */
    async isEncrypted(buffer) {
        const mupdf = await getMupdf();
        try {
            const doc = mupdf.Document.openDocument(buffer, 'application/pdf');
            const needsPwd = doc.needsPassword();
            return needsPwd;
        }
        catch {
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
    async processForClaude(buffer, passwords) {
        const mupdf = await getMupdf();
        let doc;
        try {
            doc = mupdf.Document.openDocument(buffer, 'application/pdf');
        }
        catch (e) {
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
        let passwordUsed = null;
        for (const pwd of passwords) {
            if (doc.authenticatePassword(pwd)) {
                passwordUsed = pwd;
                break;
            }
        }
        if (!passwordUsed) {
            throw new Error('password_required: PDF is password-protected and none of the candidate passwords worked');
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
                const decryptedBuffer = Buffer.from(decryptedData.buffer, decryptedData.byteOffset, decryptedData.byteLength);
                return {
                    pdfBuffer: decryptedBuffer,
                    wasEncrypted: true,
                    passwordUsed,
                    pageCount,
                };
            }
            catch (saveErr) {
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
exports.PdfService = PdfService;
//# sourceMappingURL=pdfService.js.map