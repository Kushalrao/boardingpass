import { google, gmail_v1 } from 'googleapis';
import { getTravelQuery } from '../utils/emailQuery';

export interface EmailMessage {
  id: string;
  subject: string;
  from: string;
  date: string;
  body: string;
  pdfAttachments: PdfAttachment[];
}

export interface PdfAttachment {
  filename: string;
  attachmentId: string;
  data?: Buffer;
}

export class GmailService {
  private gmail: gmail_v1.Gmail;

  constructor(accessToken: string) {
    const oauth2Client = new google.auth.OAuth2();
    oauth2Client.setCredentials({ access_token: accessToken });
    this.gmail = google.gmail({ version: 'v1', auth: oauth2Client });
  }

  async fetchTravelEmails(options: {
    batchSize: number;
    batch: number;
    year?: number;
  }): Promise<{ messages: EmailMessage[]; moreBatches: boolean; totalEmails: number }> {
    const query = getTravelQuery();
    const currentYear = options.year || new Date().getFullYear();

    // Fetch all message IDs matching the query
    let allMessageIds: gmail_v1.Schema$Message[] = [];
    let pageToken: string | undefined = undefined;
    let hasMore = true;

    while (hasMore) {
      const response: gmail_v1.Schema$ListMessagesResponse = (await this.gmail.users.messages.list({
        userId: 'me',
        q: query,
        maxResults: 500,
        pageToken,
      })).data;
      allMessageIds = allMessageIds.concat(response.messages || []);
      pageToken = response.nextPageToken || undefined;
      hasMore = !!pageToken;
    }

    // Calculate batch range
    const startIdx = (options.batch - 1) * options.batchSize;
    const endIdx = startIdx + options.batchSize;
    const batchMessageIds = allMessageIds.slice(startIdx, endIdx);
    const moreBatches = endIdx < allMessageIds.length;

    // Fetch full email details for this batch
    const messages: EmailMessage[] = [];

    for (const msgRef of batchMessageIds) {
      if (!msgRef.id) continue;

      try {
        // First check date with metadata only
        const metadata = await this.gmail.users.messages.get({
          userId: 'me',
          id: msgRef.id,
          format: 'metadata',
          metadataHeaders: ['Date'],
        });

        const dateHeader = metadata.data.payload?.headers?.find(
          (h) => h.name?.toLowerCase() === 'date'
        );

        if (!dateHeader?.value) continue;

        // Check if email is from the target year
        const emailDate = new Date(dateHeader.value);
        if (emailDate.getFullYear() !== currentYear) continue;

        // Fetch full email
        const email = await this.gmail.users.messages.get({
          userId: 'me',
          id: msgRef.id,
          format: 'full',
        });

        const headers = email.data.payload?.headers || [];
        const subjectHeader = headers.find((h) => h.name?.toLowerCase() === 'subject');
        const fromHeader = headers.find((h) => h.name?.toLowerCase() === 'from');

        // Extract body content
        let bodyContent = '';
        const bodyData = email.data.payload?.parts?.[0]?.body?.data ||
                        email.data.payload?.body?.data;
        if (bodyData) {
          bodyContent = Buffer.from(bodyData, 'base64').toString('utf-8');
        }

        // Find PDF attachments
        const pdfAttachments: PdfAttachment[] = [];
        this.findPdfParts(email.data.payload, pdfAttachments);

        messages.push({
          id: msgRef.id,
          subject: subjectHeader?.value || '',
          from: fromHeader?.value || '',
          date: dateHeader.value,
          body: bodyContent,
          pdfAttachments,
        });
      } catch (error) {
        console.error(`Error fetching email ${msgRef.id}:`, error);
        continue;
      }
    }

    return {
      messages,
      moreBatches,
      totalEmails: allMessageIds.length,
    };
  }

  async fetchPdfAttachment(messageId: string, attachmentId: string): Promise<Buffer> {
    const attachment = await this.gmail.users.messages.attachments.get({
      userId: 'me',
      messageId,
      id: attachmentId,
    });

    return Buffer.from(attachment.data.data || '', 'base64');
  }

  private findPdfParts(payload: gmail_v1.Schema$MessagePart | undefined, pdfAttachments: PdfAttachment[]): void {
    if (!payload) return;

    if (payload.mimeType === 'application/pdf' && payload.body?.attachmentId) {
      pdfAttachments.push({
        filename: payload.filename || 'attachment.pdf',
        attachmentId: payload.body.attachmentId,
      });
    }

    if (payload.parts) {
      for (const part of payload.parts) {
        this.findPdfParts(part, pdfAttachments);
      }
    }
  }
}
