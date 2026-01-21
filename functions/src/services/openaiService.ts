import OpenAI from 'openai';
import { BookingType, Booking } from '../types/bookingTypes';
import { SYSTEM_PROMPTS } from '../types/schemas';

export class OpenAIService {
  private openai: OpenAI;

  constructor(apiKey: string) {
    this.openai = new OpenAI({ apiKey });
  }

  async extractBookingData(
    content: string,
    bookingType: BookingType
  ): Promise<Partial<Booking> | null> {
    try {
      const systemPrompt = SYSTEM_PROMPTS[bookingType];

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
      } catch (parseError) {
        console.error('Failed to parse JSON from OpenAI response:', parseError);
        return null;
      }
    } catch (error) {
      console.error('OpenAI API error:', error);
      throw error;
    }
  }
}

// Currency conversion helper
export function convertToINR(amount: number, currency: string): number | null {
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
