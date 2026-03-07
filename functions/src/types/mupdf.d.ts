declare module 'mupdf' {
  export class Document {
    static openDocument(data: Buffer | ArrayBuffer | Uint8Array, magic: string): Document;
    needsPassword(): boolean;
    authenticatePassword(password: string): boolean;
    countPages(): number;
    isPDF(): boolean;
    asPDF(): PDFDocument;
  }

  export class PDFDocument extends Document {
    saveToBuffer(options?: string): Uint8Array;
  }
}
