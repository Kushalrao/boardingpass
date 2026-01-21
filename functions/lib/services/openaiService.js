"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.OpenAIService = void 0;
exports.convertToINR = convertToINR;
const openai_1 = __importDefault(require("openai"));
const schemas_1 = require("../types/schemas");
class OpenAIService {
    constructor(apiKey) {
        this.openai = new openai_1.default({ apiKey });
    }
    async extractBookingData(content, bookingType) {
        try {
            const systemPrompt = schemas_1.SYSTEM_PROMPTS[bookingType];
            const completion = await this.openai.chat.completions.create({
                model: 'gpt-3.5-turbo',
                messages: [
                    { role: 'system', content: systemPrompt },
                    { role: 'user', content: content },
                ],
                temperature: 0,
                max_tokens: 1500,
            });
            const responseContent = completion.choices[0].message.content || '';
            // Extract JSON from response
            const jsonMatch = responseContent.match(/\{[\s\S]*\}/);
            if (!jsonMatch) {
                console.warn('No JSON found in OpenAI response');
                return null;
            }
            try {
                const parsed = JSON.parse(jsonMatch[0]);
                return parsed;
            }
            catch (parseError) {
                console.error('Failed to parse JSON from OpenAI response:', parseError);
                return null;
            }
        }
        catch (error) {
            console.error('OpenAI API error:', error);
            throw error;
        }
    }
}
exports.OpenAIService = OpenAIService;
// Currency conversion helper
function convertToINR(amount, currency) {
    switch (currency.toUpperCase()) {
        case 'INR':
        case '₹':
            return amount;
        case 'USD':
        case '$':
            return amount * 83;
        case 'EUR':
        case '€':
            return amount * 90;
        case 'GBP':
        case '£':
            return amount * 105;
        default:
            return null;
    }
}
//# sourceMappingURL=openaiService.js.map