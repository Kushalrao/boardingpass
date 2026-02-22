"""
ixigo Scraper - Train live status via Firecrawl + ixigo.com
Uses Firecrawl API to fetch rendered markdown from ixigo running status pages,
then parses station-wise data including platform numbers, halt times, and delays.
"""

import os
import re
import logging
from typing import Dict, Any, Optional, List
from datetime import datetime

logger = logging.getLogger(__name__)

FIRECRAWL_AVAILABLE = False
try:
    from firecrawl import FirecrawlApp
    FIRECRAWL_AVAILABLE = True
except ImportError:
    pass


class IxigoScraper:
    """Scrapes ixigo.com train running status using Firecrawl."""

    BASE_URL = "https://www.ixigo.com/trains"

    def __init__(self, api_key: Optional[str] = None):
        if not FIRECRAWL_AVAILABLE:
            raise ImportError("firecrawl-py not installed. Run: pip install firecrawl-py")
        self.api_key = api_key or os.getenv("FIRECRAWL_API_KEY")
        if not self.api_key:
            raise ValueError("FIRECRAWL_API_KEY environment variable is required")
        self.app = FirecrawlApp(api_key=self.api_key)

    def get_live_status(self, train_number: str, date: Optional[str] = None) -> Dict[str, Any]:
        """
        Get live running status of a train from ixigo via Firecrawl.

        Args:
            train_number: 5-digit train number
            date: Optional date (unused currently, ixigo shows today's status)

        Returns:
            Dictionary with live status matching ConfirmTktScraper's format.
        """
        result = {
            "train_number": train_number,
            "train_name": None,
            "date": date or datetime.now().strftime("%d-%m-%Y"),
            "current_status": None,
            "current_location": None,
            "last_updated": None,
            "stations": [],
            "source_website": "ixigo.com",
            "error": None,
            "success": False,
        }

        try:
            url = f"{self.BASE_URL}/{train_number}/running-status"
            data = self.app.scrape_url(url, params={"formats": ["markdown"]})

            markdown = data.get("markdown", "") if isinstance(data, dict) else ""
            if not markdown:
                result["error"] = "Empty response from Firecrawl"
                return result

            logger.debug(f"ixigo markdown length: {len(markdown)} chars")

            parsed = self._parse_markdown(markdown, train_number)
            result.update(parsed)
            result["success"] = len(result.get("stations", [])) > 0

        except Exception as e:
            logger.error(f"ixigo scraper error for train {train_number}: {e}")
            result["error"] = str(e)

        return result

    def _parse_markdown(self, markdown: str, train_number: str) -> Dict[str, Any]:
        """Parse Firecrawl markdown output to extract live status data."""
        result = {
            "train_name": None,
            "current_status": None,
            "current_location": None,
            "last_updated": None,
            "stations": [],
        }

        # Extract train name
        name_patterns = [
            rf'{train_number}\s*[-–/|]\s*([A-Za-z\s]+(?:Express|Exp|Mail|Rajdhani|SF|Special)?)',
            rf'{train_number}\s+([A-Za-z\s]+?)\s+(?:Running|Live|Train)',
            rf'([A-Za-z\s]+(?:Express|Exp|Mail))\s*[-–]\s*{train_number}',
        ]
        for pattern in name_patterns:
            match = re.search(pattern, markdown, re.I)
            if match:
                name = match.group(1).strip()
                name = re.sub(r'\s*(Running|Live|Status|Train|CHANGE).*', '', name, flags=re.I).strip()
                if len(name) > 2:
                    result["train_name"] = name
                    break

        # Extract current status
        status_patterns = [
            r'(Train (?:departed from|arrived at|is at)\s+[A-Za-z\s]+)',
            r'(Running\s+[\d\s]+(?:min|hr|hour)s?\s+(?:late|early))',
            r'(Yet to start|Journey Completed|Cancelled)',
        ]
        for pattern in status_patterns:
            match = re.search(pattern, markdown, re.I)
            if match:
                result["current_status"] = match.group(1).strip()
                break

        # Extract last updated
        updated_match = re.search(
            r'(?:last\s+)?(?:updated|synced?)\s*:?\s*(\d{1,2}[\s/-]\w{3}[\s/-]\d{2,4}\s+\d{1,2}:\d{2})',
            markdown, re.I
        )
        if updated_match:
            result["last_updated"] = updated_match.group(1).strip()

        # Parse stations - try multiple strategies
        stations = self._parse_table_format(markdown)
        if not stations:
            stations = self._parse_block_format(markdown)
        if not stations:
            stations = self._parse_fallback(markdown)

        logger.debug(f"Parsed {len(stations)} stations from ixigo markdown")
        result["stations"] = stations

        # Derive current location from last departed/arrived station
        for s in reversed(stations):
            if s.get("status") in ("departed", "arrived"):
                result["current_location"] = s.get("station") or s.get("name")
                break

        return result

    def _parse_table_format(self, markdown: str) -> List[Dict[str, Any]]:
        """Parse markdown table format with station data."""
        stations = []
        lines = markdown.split("\n")

        # Find table header row
        header_idx = -1
        col_map = {}
        for i, line in enumerate(lines):
            if '|' not in line:
                continue
            lower = line.lower()
            # Check if this looks like a header row with station-related columns
            if any(kw in lower for kw in ['station', 'stn']) and any(kw in lower for kw in ['arr', 'dep', 'delay', 'platform']):
                cols = [c.strip().lower() for c in line.split('|')]
                for j, col in enumerate(cols):
                    if 'station' in col or 'stn' in col:
                        col_map['station'] = j
                    elif 'sch' in col and 'arr' in col:
                        col_map['scheduled_arrival'] = j
                    elif 'sch' in col and 'dep' in col:
                        col_map['scheduled_departure'] = j
                    elif 'act' in col and 'arr' in col:
                        col_map['actual_arrival'] = j
                    elif 'act' in col and 'dep' in col:
                        col_map['actual_departure'] = j
                    elif 'arr' in col and 'scheduled' not in col_map:
                        col_map.setdefault('arrival', j)
                    elif 'dep' in col and 'scheduled_departure' not in col_map:
                        col_map.setdefault('departure', j)
                    elif 'delay' in col or 'late' in col:
                        col_map['delay'] = j
                    elif 'platform' in col or 'pf' in col:
                        col_map['platform'] = j
                    elif 'halt' in col:
                        col_map['halt'] = j
                header_idx = i
                break

        if header_idx < 0 or 'station' not in col_map:
            return []

        # Skip separator row (---|---|---)
        start = header_idx + 1
        if start < len(lines) and re.match(r'^[\s|:-]+$', lines[start]):
            start += 1

        # Parse data rows
        for line in lines[start:]:
            if '|' not in line:
                break
            cols = [c.strip() for c in line.split('|')]
            if len(cols) <= max(col_map.values(), default=0):
                continue

            station = self._extract_station_from_cols(cols, col_map)
            if station and station.get("station"):
                stations.append(station)

        return stations

    def _extract_station_from_cols(self, cols: List[str], col_map: Dict[str, int]) -> Optional[Dict[str, Any]]:
        """Extract station data from table columns."""
        def get_col(key):
            idx = col_map.get(key)
            if idx is not None and idx < len(cols):
                val = cols[idx].strip()
                return val if val and val != '--' and val != '-' else None
            return None

        raw_station = get_col('station') or ""
        if not raw_station:
            return None

        # Extract station code from "Station Name (CODE)" pattern
        name, code = self._parse_station_name(raw_station)

        # Parse times
        arrival = get_col('scheduled_arrival') or get_col('arrival')
        departure = get_col('scheduled_departure') or get_col('departure')
        actual_arrival = get_col('actual_arrival')
        actual_departure = get_col('actual_departure')

        # Parse delay
        delay = self._parse_delay_text(get_col('delay'))

        # Parse platform
        platform = None
        platform_raw = get_col('platform')
        if platform_raw:
            pf_match = re.search(r'(\d+)', platform_raw)
            if pf_match:
                platform = int(pf_match.group(1))

        # Parse halt
        halt = get_col('halt')

        # Determine status
        status = self._determine_status(actual_arrival, actual_departure, raw_station)

        return {
            "station": name,
            "name": name,
            "code": code,
            "arrival": arrival,
            "departure": departure,
            "scheduled_arrival": arrival,
            "actual_arrival": actual_arrival,
            "delay": delay,
            "halt": halt,
            "platform": platform,
            "status": status,
        }

    def _parse_block_format(self, markdown: str) -> List[Dict[str, Any]]:
        """Parse block/list format where each station is a text block."""
        stations = []

        # Split by station patterns - look for station names with codes
        # Patterns: "**Station Name** (CODE)", "Station Name (CODE)", "### Station Name"
        blocks = re.split(
            r'(?=(?:\*{1,2}[A-Z][A-Za-z\s\.]+\*{1,2}\s*\([A-Z]{2,5}\))|'
            r'(?:^#{1,3}\s+[A-Z][A-Za-z\s\.]+)|'
            r'(?:^[A-Z][A-Za-z\s\.]+\s*\([A-Z]{2,5}\)))',
            markdown, flags=re.M
        )

        for block in blocks:
            block = block.strip()
            if not block or len(block) < 10:
                continue

            # Extract station name and code
            stn_match = re.match(
                r'\*{0,2}([A-Z][A-Za-z\s\.]+?)\*{0,2}\s*\(([A-Z]{2,5})\)',
                block
            )
            if not stn_match:
                stn_match = re.match(r'#{1,3}\s+([A-Z][A-Za-z\s\.]+?)(?:\s*\(([A-Z]{2,5})\))?', block)
            if not stn_match:
                continue

            name = stn_match.group(1).strip()
            code = stn_match.group(2) if stn_match.lastindex >= 2 else None

            # Extract times from the block
            times = re.findall(r'(\d{1,2}:\d{2})', block)

            # Extract platform
            platform = None
            pf_match = re.search(r'(?:platform|pf)\s*:?\s*(\d+)', block, re.I)
            if pf_match:
                platform = int(pf_match.group(1))

            # Extract delay
            delay = None
            delay_match = re.search(
                r'(?:delay|late)\s*(?:by)?\s*:?\s*(?:(\d+)\s*hr?\s*)?(\d+)?\s*min',
                block, re.I
            )
            if delay_match:
                hrs = int(delay_match.group(1)) if delay_match.group(1) else 0
                mins = int(delay_match.group(2)) if delay_match.group(2) else 0
                delay = hrs * 60 + mins
            elif re.search(r'on\s*time|right\s*time', block, re.I):
                delay = 0

            # Extract halt
            halt = None
            halt_match = re.search(r'halt\s*:?\s*(\d+\s*min)', block, re.I)
            if halt_match:
                halt = halt_match.group(1)

            # Determine status
            status = "upcoming"
            if re.search(r'departed|left', block, re.I):
                status = "departed"
            elif re.search(r'arrived|reached', block, re.I):
                status = "arrived"
            elif re.search(r'cancelled', block, re.I):
                status = "cancelled"

            station = {
                "station": name,
                "name": name,
                "code": code,
                "arrival": times[0] if len(times) > 0 else None,
                "departure": times[1] if len(times) > 1 else None,
                "scheduled_arrival": times[0] if len(times) > 0 else None,
                "actual_arrival": times[2] if len(times) > 2 else None,
                "delay": delay,
                "halt": halt,
                "platform": platform,
                "status": status,
            }
            stations.append(station)

        return stations

    def _parse_fallback(self, markdown: str) -> List[Dict[str, Any]]:
        """Last-resort: scan for station code patterns and extract nearby data."""
        stations = []
        seen_codes = set()

        for match in re.finditer(r'([A-Za-z][A-Za-z\s\.]{2,30}?)\s*\(([A-Z]{2,5})\)', markdown):
            name = match.group(1).strip()
            code = match.group(2)

            if code in seen_codes:
                continue
            seen_codes.add(code)

            # Skip non-station patterns (e.g., abbreviations in text)
            if any(skip in name.lower() for skip in ['irctc', 'pnr', 'book', 'app', 'download']):
                continue

            # Look in surrounding context for data
            start = max(0, match.start() - 50)
            end = min(len(markdown), match.end() + 300)
            context = markdown[start:end]

            times = re.findall(r'(\d{1,2}:\d{2})', context)

            platform = None
            pf_match = re.search(r'(?:platform|pf)\s*:?\s*(\d+)', context, re.I)
            if pf_match:
                platform = int(pf_match.group(1))

            delay = None
            delay_match = re.search(r'(?:(\d+)\s*hr?\s*)?(\d+)\s*min\s*(?:late|delay)', context, re.I)
            if delay_match:
                hrs = int(delay_match.group(1)) if delay_match.group(1) else 0
                mins = int(delay_match.group(2)) if delay_match.group(2) else 0
                delay = hrs * 60 + mins
            elif re.search(r'on\s*time|right\s*time', context, re.I):
                delay = 0

            station = {
                "station": name,
                "name": name,
                "code": code,
                "arrival": times[0] if len(times) > 0 else None,
                "departure": times[1] if len(times) > 1 else None,
                "scheduled_arrival": times[0] if len(times) > 0 else None,
                "actual_arrival": None,
                "delay": delay,
                "halt": None,
                "platform": platform,
                "status": "upcoming",
            }
            stations.append(station)

        return stations

    def _parse_station_name(self, raw: str) -> tuple:
        """Extract station name and code from strings like 'Station Name (CODE)'."""
        match = re.match(r'(.+?)\s*\(([A-Z]{2,5})\)', raw)
        if match:
            return match.group(1).strip().strip('*'), match.group(2)
        # Clean markdown formatting
        name = re.sub(r'\*+', '', raw).strip()
        return name, ""

    def _parse_delay_text(self, text: Optional[str]) -> Optional[int]:
        """Parse delay text into minutes."""
        if not text:
            return None
        text = text.strip().lower()
        if text in ('on time', 'right time', 'rt', '--', ''):
            return 0
        # "2 hr 30 min" or "2h 30m"
        match = re.search(r'(?:(\d+)\s*(?:hr?|hour)s?\s*)?(\d+)\s*(?:min|m)', text)
        if match:
            hrs = int(match.group(1)) if match.group(1) else 0
            mins = int(match.group(2)) if match.group(2) else 0
            return hrs * 60 + mins
        # Just a number
        match = re.search(r'(\d+)', text)
        if match:
            return int(match.group(1))
        return None

    def _determine_status(self, actual_arrival: Optional[str], actual_departure: Optional[str],
                          raw_text: str = "") -> str:
        """Determine station status from available data."""
        raw_lower = raw_text.lower()
        if 'cancel' in raw_lower:
            return "cancelled"
        if actual_departure:
            return "departed"
        if actual_arrival:
            return "arrived"
        return "upcoming"


def main():
    """Test the ixigo scraper."""
    import json
    import sys

    train = sys.argv[1] if len(sys.argv) > 1 else "12301"

    # Check for --raw flag to dump raw markdown
    dump_raw = '--raw' in sys.argv

    print(f"Fetching live status from ixigo for train {train}...")

    try:
        scraper = IxigoScraper()
        if dump_raw:
            url = f"{scraper.BASE_URL}/{train}/running-status"
            data = scraper.app.scrape_url(url, params={"formats": ["markdown"]})
            markdown = data.get("markdown", "") if isinstance(data, dict) else ""
            print("\n=== RAW MARKDOWN ===")
            print(markdown)
            print("=== END MARKDOWN ===\n")

        result = scraper.get_live_status(train)
        print(json.dumps(result, indent=2, default=str))

        if result.get("stations"):
            print(f"\n{'='*80}")
            print(f"  IXIGO LIVE STATUS - {result.get('train_name', train)}")
            print(f"{'='*80}")
            print(f"  Status: {result.get('current_status', 'N/A')}")
            print(f"  Updated: {result.get('last_updated', 'N/A')}")
            print(f"\n{'Station':<25} {'Code':<6} {'Arr':>6} {'Dep':>6} {'Delay':>8} {'PF':>4} {'Halt':>8} {'Status':<10}")
            print(f"{'─'*85}")
            for s in result["stations"]:
                name = (s.get('station') or s.get('name', ''))[:24]
                code = s.get('code', '') or ''
                arr = s.get('arrival') or '--'
                dep = s.get('departure') or '--'
                delay = f"{s['delay']} min" if s.get('delay') is not None else '--'
                pf = str(s['platform']) if s.get('platform') else '--'
                halt = s.get('halt') or '--'
                status = s.get('status', 'upcoming')
                print(f"{name:<25} {code:<6} {arr:>6} {dep:>6} {delay:>8} {pf:>4} {halt:>8} {status:<10}")

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
