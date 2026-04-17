/**
 * Test script — uses compiled detector from lib/ directly.
 * Usage: node testDetector.js <access-token>
 */
const { google } = require('googleapis');
const { detectFlightEmail } = require('./lib/services/flightDetector');

const ACCESS_TOKEN = process.argv[2];
if (!ACCESS_TOKEN) {
  console.error('Usage: node testDetector.js <access-token>');
  process.exit(1);
}

// --- Gmail helpers (same as gmailService but standalone) ---

function stripHtmlTags(html) {
  return html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&#?\w+;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function findPartByMimeType(payload, mimeType) {
  if (payload.mimeType === mimeType && payload.body && payload.body.data) return payload;
  if (payload.parts) {
    for (const part of payload.parts) {
      const found = findPartByMimeType(part, mimeType);
      if (found) return found;
    }
  }
  return null;
}

function extractBody(payload) {
  if (!payload) return '';
  const plainPart = findPartByMimeType(payload, 'text/plain');
  if (plainPart && plainPart.body && plainPart.body.data) {
    return Buffer.from(plainPart.body.data, 'base64').toString('utf-8');
  }
  const htmlPart = findPartByMimeType(payload, 'text/html');
  if (htmlPart && htmlPart.body && htmlPart.body.data) {
    return stripHtmlTags(Buffer.from(htmlPart.body.data, 'base64').toString('utf-8'));
  }
  if (payload.body && payload.body.data) {
    return Buffer.from(payload.body.data, 'base64').toString('utf-8');
  }
  return '';
}

// --- Main ---

async function main() {
  const oauth2Client = new google.auth.OAuth2();
  oauth2Client.setCredentials({ access_token: ACCESS_TOKEN });
  const gmail = google.gmail({ version: 'v1', auth: oauth2Client });

  const query = [
    'from:(goindigo.in OR airindia.com OR airindia.in OR spicejet.com OR airvistara.com OR airasia.com OR akasaair.com OR allianceair.in OR starair.in OR flybigair.com',
    'OR emirates.com OR qatarairways.com OR etihad.com OR flydubai.com OR omanair.com OR saudia.com OR gulfair.com',
    'OR singaporeair.com OR malaysiaairlines.com OR thaiairways.com OR cathaypacific.com OR srilankan.com',
    'OR lufthansa.com OR britishairways.com OR klm.com OR airfrance.com OR turkishairlines.com OR ryanair.com OR easyjet.com',
    'OR united.com OR delta.com OR aa.com OR southwest.com OR jetblue.com OR aircanada.com',
    'OR jal.com OR koreanair.com OR qantas.com',
    'OR makemytrip.com OR goibibo.com OR cleartrip.com OR easemytrip.com OR yatra.com OR ixigo.com OR via.com OR paytm.com',
    'OR happyeasygo.com OR abhibus.com OR thomascook.in OR sotc.in OR akbartravels.com OR musafir.com OR adanione.com OR udchalo.com',
    'OR phonepe.com OR amazon.in OR flipkart.com',
    'OR expedia.com OR booking.com OR kayak.com OR skyscanner.com OR trip.com OR kiwi.com OR traveloka.com OR agoda.com)',
    'subject:(booking OR confirmation OR e-ticket OR eticket OR itinerary OR PNR OR flight OR "boarding pass" OR ticket OR reservation)',
    '-subject:(deal OR offer OR sale OR "price alert" OR newsletter OR unsubscribe)',
  ].join(' ');

  console.log('Searching Gmail for flight-related emails...\n');

  let allMessageIds = [];
  let pageToken = undefined;
  let hasMore = true;

  while (hasMore) {
    const response = await gmail.users.messages.list({
      userId: 'me',
      q: query,
      maxResults: 500,
      pageToken,
    });
    allMessageIds = allMessageIds.concat(response.data.messages || []);
    pageToken = response.data.nextPageToken || undefined;
    hasMore = !!pageToken;
  }

  console.log(`Found ${allMessageIds.length} emails matching the Gmail query.\n`);

  if (allMessageIds.length === 0) {
    console.log('No matching emails found.');
    const fs = require('fs');
    const outputPath = require('path').join(__dirname, 'detected_flights.json');
    fs.writeFileSync(outputPath, JSON.stringify({ totalScanned: 0, detected: [], rejected: [] }, null, 2));
    require('child_process').execSync(`open -R "${outputPath}"`);
    return;
  }

  const cap = allMessageIds.length;  // scan all
  console.log(`Processing first ${cap} emails...\n`);

  const detected = [];
  const rejected = [];

  for (let i = 0; i < cap; i++) {
    const msgRef = allMessageIds[i];
    if (!msgRef.id) continue;

    try {
      const emailResponse = await gmail.users.messages.get({
        userId: 'me',
        id: msgRef.id,
        format: 'full',
      });

      const headers = emailResponse.data.payload?.headers || [];
      const subject = (headers.find(h => h.name?.toLowerCase() === 'subject') || {}).value || '';
      const from = (headers.find(h => h.name?.toLowerCase() === 'from') || {}).value || '';
      const date = (headers.find(h => h.name?.toLowerCase() === 'date') || {}).value || '';
      const body = extractBody(emailResponse.data.payload);

      const email = { id: msgRef.id, subject, from, date, body, pdfAttachments: [] };
      const result = detectFlightEmail(email);

      const entry = {
        gmailMessageId: msgRef.id,
        subject,
        from,
        date,
        score: result.score,
        confidence: result.confidence,
        senderCategory: result.senderCategory,
        senderDomain: result.senderDomain,
        matchedSignals: result.matchedSignals,
        body: body.substring(0, 5000),
        bodyPreview: body.substring(0, 200),
      };

      if (result.isFlightEmail) {
        detected.push(entry);
        console.log(`[${i + 1}/${cap}] DETECTED [${result.confidence}] score=${result.score} — "${subject}"`);
      } else {
        rejected.push(entry);
        console.log(`[${i + 1}/${cap}] rejected  score=${result.score} signals=[${result.matchedSignals.join(', ')}] — "${subject}"`);
      }
    } catch (err) {
      console.error(`[${i + 1}/${cap}] ERROR fetching ${msgRef.id}: ${err.message}`);
    }
  }

  console.log(`\n========================================`);
  console.log(`RESULTS: ${detected.length} detected, ${rejected.length} rejected out of ${cap} scanned`);
  console.log(`========================================\n`);

  const output = {
    scanDate: new Date().toISOString(),
    totalInGmail: allMessageIds.length,
    totalScanned: cap,
    totalDetected: detected.length,
    totalRejected: rejected.length,
    detected,
    rejected,
  };

  const fs = require('fs');
  const path = require('path');
  const outputPath = path.join(__dirname, 'detected_flights.json');
  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
  console.log(`Results written to: ${outputPath}`);

  require('child_process').execSync(`open -R "${outputPath}"`);
  console.log('Opened in Finder.');
}

main().catch(err => {
  console.error('Fatal error:', err.message);
  if (err.message.includes('invalid_grant') || err.message.includes('Invalid Credentials')) {
    console.error('\nThe access token has expired. Get a new one from the OAuth Playground.');
  }
  process.exit(1);
});
