import { google, gmail_v1 } from 'googleapis';

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

  /**
   * Generic method to fetch emails matching any query, with batching.
   */
  async fetchEmails(query: string, options: {
    batchSize: number;
    batch: number;
  }): Promise<{ messages: EmailMessage[]; moreBatches: boolean; totalEmails: number }> {
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
        const email = await this.gmail.users.messages.get({
          userId: 'me',
          id: msgRef.id,
          format: 'full',
        });

        const headers = email.data.payload?.headers || [];
        const subjectHeader = headers.find((h) => h.name?.toLowerCase() === 'subject');
        const fromHeader = headers.find((h) => h.name?.toLowerCase() === 'from');
        const dateHeader = headers.find((h) => h.name?.toLowerCase() === 'date');

        // Extract body content (text/plain preferred, HTML fallback)
        const bodyContent = extractBody(email.data.payload);

        // Find PDF attachments
        const pdfAttachments: PdfAttachment[] = [];
        this.findPdfParts(email.data.payload, pdfAttachments);

        messages.push({
          id: msgRef.id,
          subject: subjectHeader?.value || '',
          from: fromHeader?.value || '',
          date: dateHeader?.value || '',
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

  /**
   * Fetch a single message by ID
   */
  async fetchMessageById(messageId: string): Promise<EmailMessage | null> {
    try {
      const email = await this.gmail.users.messages.get({
        userId: 'me',
        id: messageId,
        format: 'full',
      });

      const headers = email.data.payload?.headers || [];
      const subjectHeader = headers.find((h) => h.name?.toLowerCase() === 'subject');
      const fromHeader = headers.find((h) => h.name?.toLowerCase() === 'from');
      const dateHeader = headers.find((h) => h.name?.toLowerCase() === 'date');

      // Extract body content (text/plain preferred, HTML fallback)
      const bodyContent = extractBody(email.data.payload);

      // Find PDF attachments
      const pdfAttachments: PdfAttachment[] = [];
      this.findPdfParts(email.data.payload, pdfAttachments);

      return {
        id: messageId,
        subject: subjectHeader?.value || '',
        from: fromHeader?.value || '',
        date: dateHeader?.value || '',
        body: bodyContent,
        pdfAttachments,
      };
    } catch (error) {
      console.error(`Error fetching message ${messageId}:`, error);
      return null;
    }
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

// ============================================
// Body extraction helpers
// ============================================

/**
 * Extracts body text from an email payload.
 * Prefers text/plain, falls back to HTML with tag stripping.
 */
function extractBody(payload: gmail_v1.Schema$MessagePart | undefined): string {
  if (!payload) return '';

  // Try text/plain first
  const plainPart = findPartByMimeType(payload, 'text/plain');
  if (plainPart?.body?.data) {
    return Buffer.from(plainPart.body.data, 'base64').toString('utf-8');
  }

  // Fallback: text/html with tag stripping
  const htmlPart = findPartByMimeType(payload, 'text/html');
  if (htmlPart?.body?.data) {
    const html = Buffer.from(htmlPart.body.data, 'base64').toString('utf-8');
    return stripHtmlTags(html);
  }

  // Last resort: root body data (simple non-multipart emails)
  if (payload.body?.data) {
    return Buffer.from(payload.body.data, 'base64').toString('utf-8');
  }

  return '';
}

/**
 * Recursively finds a MIME part by type in the email payload tree.
 */
function findPartByMimeType(
  payload: gmail_v1.Schema$MessagePart,
  mimeType: string
): gmail_v1.Schema$MessagePart | undefined {
  if (payload.mimeType === mimeType && payload.body?.data) {
    return payload;
  }

  if (payload.parts) {
    for (const part of payload.parts) {
      const found = findPartByMimeType(part, mimeType);
      if (found) return found;
    }
  }

  return undefined;
}

/**
 * Basic HTML tag stripping for keyword detection.
 * Not a full parser — just enough to extract readable text.
 */
function stripHtmlTags(html: string): string {
  return html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')  // Remove style blocks
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '') // Remove script blocks
    .replace(/<[^>]+>/g, ' ')                          // Remove tags
    .replace(/&nbsp;/gi, ' ')                          // Replace &nbsp;
    .replace(/&amp;/gi, '&')                           // Replace &amp;
    .replace(/&lt;/gi, '<')                            // Replace &lt;
    .replace(/&gt;/gi, '>')                            // Replace &gt;
    .replace(/&#?\w+;/g, ' ')                          // Remove other HTML entities
    .replace(/\s+/g, ' ')                              // Collapse whitespace
    .trim();
}
