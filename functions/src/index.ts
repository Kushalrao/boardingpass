import * as functions from 'firebase-functions';
import { GmailService } from './services/gmailService';
import { PdfService } from './services/pdfService';
import { OpenAIService, convertToINR } from './services/openaiService';
import { detectBookingType } from './utils/bookingDetector';
import { Booking, TravelAnalysisResponse, AnalyzeTravelRequest } from './types/bookingTypes';

// OpenAI API Key from environment
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || functions.config().openai?.key;

export const analyzeTravel = functions
  .runWith({
    timeoutSeconds: 540, // 9 minutes (max for HTTP functions)
    memory: '1GB',
  })
  .https.onCall(async (data: AnalyzeTravelRequest, context): Promise<TravelAnalysisResponse> => {
    // Validate request
    if (!data.accessToken) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Access token is required'
      );
    }

    if (!OPENAI_API_KEY) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'OpenAI API key not configured'
      );
    }

    const options = {
      batchSize: data.options?.batchSize || 5,
      batch: data.options?.batch || 1,
      year: data.options?.year || new Date().getFullYear(),
    };

    console.log(`Processing batch ${options.batch} with size ${options.batchSize}`);

    // Initialize services
    const gmailService = new GmailService(data.accessToken);
    const pdfService = new PdfService();
    const openaiService = new OpenAIService(OPENAI_API_KEY);

    try {
      // Fetch travel emails
      const { messages, moreBatches, totalEmails } = await gmailService.fetchTravelEmails(options);
      console.log(`Found ${messages.length} emails in this batch, ${totalEmails} total`);

      const travels: Booking[] = [];

      for (const message of messages) {
        console.log(`Processing: ${message.subject}`);

        // Detect booking type
        const bookingType = detectBookingType(message.subject, message.from);
        console.log(`Detected type: ${bookingType}`);

        let content = '';
        let pdfParseStatus = 'not_attempted';
        let pdfParseError = '';

        // Try PDF attachments first
        if (message.pdfAttachments.length > 0) {
          pdfParseStatus = 'attempted';

          for (const pdf of message.pdfAttachments) {
            try {
              const pdfBuffer = await gmailService.fetchPdfAttachment(message.id, pdf.attachmentId);
              content = await pdfService.extractText(pdfBuffer);
              pdfParseStatus = 'success';
              console.log(`Extracted ${content.length} chars from PDF`);
              break; // Use first successful PDF
            } catch (error: any) {
              pdfParseStatus = 'error';
              pdfParseError = error.message;
              console.error(`PDF parse error: ${error.message}`);
            }
          }
        }

        // Fall back to email body if no PDF content
        if (!content && message.body && message.body.length > 100) {
          content = message.body;
          pdfParseStatus = 'email_body';
        }

        if (!content) {
          console.log('No content to analyze, skipping');
          continue;
        }

        // Extract booking data using OpenAI
        try {
          const bookingData = await openaiService.extractBookingData(content, bookingType);

          if (bookingData && Object.keys(bookingData).length > 0) {
            // Extract amount and convert to INR
            let amount: number | undefined;
            let currency: string | undefined;
            let amountINR: number | undefined;

            if ('total_amount_paid' in bookingData && bookingData.total_amount_paid) {
              amount = bookingData.total_amount_paid.amount ?? undefined;
              currency = bookingData.total_amount_paid.currency ?? undefined;
            } else if ('total_amount' in bookingData && bookingData.total_amount) {
              amount = (bookingData.total_amount as any).amount ?? undefined;
              currency = (bookingData.total_amount as any).currency ?? undefined;
            } else if ('fees' in bookingData && bookingData.fees) {
              amount = (bookingData.fees as any).amount ?? undefined;
              currency = (bookingData.fees as any).currency ?? undefined;
            }

            if (amount && currency) {
              amountINR = convertToINR(amount, currency) ?? undefined;
            }

            // Extract origin/destination
            let origin: string | undefined;
            let destination: string | undefined;

            if ('flights' in bookingData && bookingData.flights?.[0]) {
              origin = bookingData.flights[0].departure?.city ?? undefined;
              destination = bookingData.flights[0].arrival?.city ?? undefined;
            } else if ('departure' in bookingData && 'arrival' in bookingData) {
              origin = (bookingData.departure as any)?.city || (bookingData.departure as any)?.location;
              destination = (bookingData.arrival as any)?.city || (bookingData.arrival as any)?.location;
            } else if ('address' in bookingData) {
              destination = (bookingData.address as any)?.city;
            } else if ('location' in bookingData) {
              destination = (bookingData.location as any)?.city;
            } else if ('venue' in bookingData) {
              destination = (bookingData.venue as any)?.city;
            } else if ('country' in bookingData) {
              destination = bookingData.country as string;
            }

            travels.push({
              ...bookingData,
              booking_type: bookingType,
              date: message.date,
              pdfParseStatus,
              pdfParseError,
              origin,
              destination,
              amount,
              currency,
              amountINR,
            } as Booking);

            console.log(`Successfully extracted ${bookingType} booking`);
          }
        } catch (error: any) {
          console.error(`OpenAI extraction error: ${error.message}`);
        }
      }

      // Sort by date
      travels.sort((a, b) => new Date(a.date || 0).getTime() - new Date(b.date || 0).getTime());

      console.log(`Returning ${travels.length} bookings`);

      return {
        travels,
        moreBatches,
        nextBatch: moreBatches ? options.batch + 1 : null,
        totalEmails,
      };
    } catch (error: any) {
      console.error('Travel analysis error:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Failed to analyze travel data: ${error.message}`
      );
    }
  });
