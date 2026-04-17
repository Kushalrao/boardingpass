/**
 * Test grouper — reads detected_flights.json and groups into unique flights.
 * Usage: node testGrouper.js
 */
const { groupFlightEmails } = require('./lib/services/flightGrouper');
const fs = require('fs');
const path = require('path');

const inputPath = path.join(__dirname, 'detected_flights.json');
if (!fs.existsSync(inputPath)) {
  console.error('detected_flights.json not found. Run testDetector.js first.');
  process.exit(1);
}

const data = JSON.parse(fs.readFileSync(inputPath, 'utf-8'));
console.log(`Loaded ${data.detected.length} detected emails.\n`);

// Convert to the format grouper expects (needs body from bodyPreview)
const emails = data.detected.map(d => ({
  gmailMessageId: d.gmailMessageId,
  subject: d.subject,
  from: d.from,
  date: d.date,
  body: d.body || d.bodyPreview || '',
}));

const { flights, orphans } = groupFlightEmails(emails);

console.log(`========================================`);
console.log(`GROUPED: ${flights.length} unique flights`);
console.log(`ORPHANS: ${orphans.length} emails with no identifiers`);
console.log(`========================================\n`);

for (const flight of flights) {
  const pnrStr = flight.pnrs.length > 0 ? `PNR: ${flight.pnrs.join(', ')}` : '';
  const bidStr = flight.bookingIds.length > 0 ? `BID: ${flight.bookingIds.join(', ')}` : '';
  const tidStr = flight.tripIds.length > 0 ? `TID: ${flight.tripIds.join(', ')}` : '';
  const ids = [pnrStr, bidStr, tidStr].filter(Boolean).join(' | ');

  const routeStr = flight.route ? `${flight.route.from} → ${flight.route.to}` : 'unknown route';
  const dateStr = flight.flightDate || 'unknown date';
  const airlineStr = flight.airline || 'unknown airline';

  console.log(`Flight #${flight.id}: ${airlineStr} ${routeStr} on ${dateStr}`);
  console.log(`  ${ids}`);
  console.log(`  Flight numbers: ${flight.flightNumbers.join(', ') || 'none'}`);
  console.log(`  Emails: ${flight.emailCount}`);
  flight.emailSubjects.forEach(s => console.log(`    - ${s}`));
  console.log();
}

if (orphans.length > 0) {
  console.log(`=== ORPHANS (no identifiers) ===\n`);
  orphans.forEach(o => console.log(`  - "${o.subject}" from ${o.from}`));
  console.log();
}

// Write output
const output = {
  groupedDate: new Date().toISOString(),
  totalEmails: data.detected.length,
  uniqueFlights: flights.length,
  orphanCount: orphans.length,
  flights,
  orphans: orphans.map(o => ({ subject: o.subject, from: o.from, date: o.date })),
};

const outputPath = path.join(__dirname, 'grouped_flights.json');
fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
console.log(`Results written to: ${outputPath}`);

require('child_process').execSync(`open -a "TextEdit" "${outputPath}"`);
