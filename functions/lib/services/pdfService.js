"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PdfService = void 0;
const pdf_parse_1 = __importDefault(require("pdf-parse"));
class PdfService {
    async extractText(pdfBuffer) {
        try {
            const data = await (0, pdf_parse_1.default)(pdfBuffer);
            return data.text;
        }
        catch (error) {
            console.error('Error parsing PDF:', error);
            throw new Error('Failed to parse PDF');
        }
    }
}
exports.PdfService = PdfService;
//# sourceMappingURL=pdfService.js.map