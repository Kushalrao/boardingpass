#!/usr/bin/env python3
"""
ConfirmTkt Scraper - Enhanced train data scraping.
Provides train schedule, live status, and PNR status.
"""

import os
import re
import time
from typing import Dict, Any, List, Optional
from datetime import datetime

try:
    from selenium import webdriver
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.common.exceptions import TimeoutException, NoSuchElementException
    SELENIUM_AVAILABLE = True
except ImportError:
    SELENIUM_AVAILABLE = False

try:
    from webdriver_manager.chrome import ChromeDriverManager
    WEBDRIVER_MANAGER_AVAILABLE = True
except ImportError:
    WEBDRIVER_MANAGER_AVAILABLE = False


class ConfirmTktScraper:
    """Enhanced ConfirmTkt scraper for train data."""

    BASE_URL = "https://www.confirmtkt.com"

    def __init__(self, headless: bool = True):
        if not SELENIUM_AVAILABLE:
            raise ImportError("Selenium not installed. Run: pip install selenium webdriver-manager")
        self.headless = headless
        self.driver = None

    def _setup_driver(self):
        """Initialize Chrome WebDriver."""
        options = Options()
        if self.headless:
            options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--window-size=1920,1080")
        options.add_argument("--disable-blink-features=AutomationControlled")
        options.add_argument("--disable-gpu")
        options.add_argument("--disable-software-rasterizer")
        options.add_argument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

        # Check for Cloud Run environment (Chromium)
        chrome_bin = os.environ.get('CHROME_BIN')
        chromedriver_path = os.environ.get('CHROMEDRIVER_PATH')

        if chrome_bin:
            options.binary_location = chrome_bin

        if chromedriver_path:
            service = Service(executable_path=chromedriver_path)
            self.driver = webdriver.Chrome(service=service, options=options)
        elif WEBDRIVER_MANAGER_AVAILABLE:
            service = Service(ChromeDriverManager().install())
            self.driver = webdriver.Chrome(service=service, options=options)
        else:
            self.driver = webdriver.Chrome(options=options)

    def _close_driver(self):
        """Close the WebDriver."""
        if self.driver:
            self.driver.quit()
            self.driver = None

    def get_train_schedule(self, train_number: str) -> Dict[str, Any]:
        """
        Get detailed train schedule with station-wise information.

        Args:
            train_number: 5-digit train number

        Returns:
            Dictionary with train schedule including:
            - Train name, number
            - Source/destination
            - Running days
            - Station-wise: arrival, departure, halt, distance, avg delay
        """
        result = {
            "train_number": train_number,
            "train_name": None,
            "source": None,
            "source_code": None,
            "destination": None,
            "destination_code": None,
            "departure": None,
            "arrival": None,
            "running_days": [],
            "total_distance": None,
            "stations": [],
            "source_website": "confirmtkt.com",
            "last_updated": datetime.now().isoformat(),
            "error": None,
            "success": False
        }

        try:
            self._setup_driver()
            url = f"{self.BASE_URL}/train-schedule/{train_number}"
            self.driver.get(url)
            time.sleep(4)

            page_text = self.driver.find_element(By.TAG_NAME, "body").text

            # Check for invalid train
            if "not found" in page_text.lower() or "invalid" in page_text.lower():
                result["error"] = "Train not found"
                return result

            # Extract train name
            name_match = re.search(rf'{train_number}\s*[-–]\s*([A-Z\s]+(?:EXP(?:RES(?:S)?)?|MAIL|RAJ(?:DHANI)?|SF|SPECIAL)?)', page_text)
            if name_match:
                name = name_match.group(1).strip()
                name = re.sub(r'\s*(CHANGE|Schedule|Live).*', '', name, flags=re.I)
                name = name.split('\n')[0].strip()
                result["train_name"] = name

            # Extract route (e.g., "Kolkata Howrah Junction to New Delhi")
            route_match = re.search(r'([A-Za-z\s]+(?:Junction|Terminus|Central)?)\s+to\s+([A-Za-z\s]+(?:Junction|Terminus|Central)?)', page_text)
            if route_match:
                result["source"] = route_match.group(1).strip()
                result["destination"] = route_match.group(2).strip()

            # Extract running days
            days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            for day in days:
                if day in page_text:
                    result["running_days"].append(day)

            # Parse station table
            lines = page_text.split('\n')
            for line in lines:
                # Match pattern: "1 HOWRAH JN - HWH 00:00 16:50 -- 0.00 km 01 Min 1"
                # or "2 ASANSOL JN - ASN 18:47 18:49 02:00 200.00 km 04 Min 1"
                station_match = re.match(
                    r'^(\d+)\s+([A-Z\s\.\-]+)\s+-\s+([A-Z]{2,5})\s+(\d{2}:\d{2}|--)\s+(\d{2}:\d{2}|--)\s+([\d:]+|--)\s+([\d.]+)\s*km\s*(.*?)(\d)$',
                    line.strip()
                )
                if station_match:
                    sno, name, code, arr, dep, halt, dist, delay_info, day = station_match.groups()

                    # Parse average delay
                    avg_delay = None
                    delay_match = re.search(r'(\d+)\s*Min', delay_info)
                    if delay_match:
                        avg_delay = int(delay_match.group(1))

                    station = {
                        "sno": int(sno),
                        "station_name": name.strip(),
                        "station_code": code,
                        "arrival": arr if arr != '--' else None,
                        "departure": dep if dep != '--' else None,
                        "halt_time": halt if halt != '--' else None,
                        "distance_km": float(dist),
                        "avg_delay_mins": avg_delay,
                        "day": int(day)
                    }
                    result["stations"].append(station)
                    continue

                # Fallback: more flexible pattern without "km" suffix
                # e.g. "1 HOWRAH JN HWH -- 16:50 -- 0 1"
                station_match2 = re.match(
                    r'^(\d+)\s+([A-Z][A-Z\s\.\-]+?)\s+([A-Z]{2,5})\s+(\d{2}:\d{2}|--)\s+(\d{2}:\d{2}|--)\s+([\d:]+|--)\s+([\d.]+)\s+(\d)$',
                    line.strip()
                )
                if station_match2:
                    sno, name, code, arr, dep, halt, dist, day = station_match2.groups()
                    station = {
                        "sno": int(sno),
                        "station_name": name.strip().rstrip(' -'),
                        "station_code": code,
                        "arrival": arr if arr != '--' else None,
                        "departure": dep if dep != '--' else None,
                        "halt_time": halt if halt != '--' else None,
                        "distance_km": float(dist),
                        "avg_delay_mins": None,
                        "day": int(day)
                    }
                    result["stations"].append(station)

            # Set source/destination codes from stations
            if result["stations"]:
                result["source_code"] = result["stations"][0]["station_code"]
                result["destination_code"] = result["stations"][-1]["station_code"]
                result["departure"] = result["stations"][0]["departure"]
                result["arrival"] = result["stations"][-1]["arrival"]
                result["total_distance"] = f"{result['stations'][-1]['distance_km']} km"

            result["success"] = len(result["stations"]) > 0

        except TimeoutException:
            result["error"] = "Page load timeout"
        except Exception as e:
            result["error"] = str(e)
        finally:
            self._close_driver()

        return result

    def get_live_status(self, train_number: str, date: Optional[str] = None) -> Dict[str, Any]:
        """
        Get live running status of a train.

        Args:
            train_number: 5-digit train number
            date: Optional date (defaults to today)

        Returns:
            Dictionary with live status including:
            - Current location
            - Delay information
            - Station-wise live updates
        """
        result = {
            "train_number": train_number,
            "train_name": None,
            "date": date or datetime.now().strftime("%d-%m-%Y"),
            "current_status": None,
            "current_location": None,
            "last_updated": None,
            "stations": [],
            "source_website": "confirmtkt.com",
            "error": None,
            "success": False
        }

        try:
            self._setup_driver()
            url = f"{self.BASE_URL}/train-running-status/{train_number}"
            self.driver.get(url)
            time.sleep(3)

            # Click submit to get today's status
            try:
                submit_buttons = self.driver.find_elements(By.TAG_NAME, "button")
                for btn in submit_buttons:
                    btn_text = btn.text.lower()
                    if 'submit' in btn_text or 'check' in btn_text or 'status' in btn_text:
                        btn.click()
                        time.sleep(4)
                        break
            except:
                pass

            page_text = self.driver.find_element(By.TAG_NAME, "body").text

            # Extract train name - look for pattern like "12301 - RAJDHANI EXPRESS" or "12301 Train"
            name_patterns = [
                rf'{train_number}\s*[-–]\s*([A-Z][A-Z\s]+(?:EXP(?:RES(?:S)?)?|MAIL|RAJ(?:DHANI)?|SF|SPECIAL)?)',
                rf'{train_number}\s+([A-Z][A-Z\s]+(?:running|Train))',
            ]
            for pattern in name_patterns:
                name_match = re.search(pattern, page_text)
                if name_match:
                    name = name_match.group(1).strip()
                    # Clean up name - remove trailing noise
                    name = re.sub(r'\s*(running|Train|CHANGE|Live|Status).*', '', name, flags=re.I)
                    name = name.split('\n')[0].strip()
                    if len(name) > 2:
                        result["train_name"] = name
                        break

            # Fallback: try to find train name from page title
            if not result["train_name"]:
                title_match = re.search(rf'{train_number}\s+([A-Z][A-Z\s]+)\s+(?:running|live|status)', page_text, re.I)
                if title_match:
                    name = title_match.group(1).strip()
                    name = name.split('\n')[0].strip()
                    result["train_name"] = name

            # Extract current status (e.g., "Train departed from HAJIGARH")
            status_patterns = [
                r'(Train departed from [A-Z\s]+)',
                r'(Train arrived at [A-Z\s]+)',
                r'(Train is at [A-Z\s]+)',
                r'(Yet to start)',
                r'(Journey Completed)',
                r'(Cancelled)',
                r'(Running [\d\s]+ (?:min|hr|hour)s? (?:late|early))',
            ]
            for pattern in status_patterns:
                match = re.search(pattern, page_text, re.I)
                if match:
                    result["current_status"] = match.group(1).strip()
                    break

            # Extract current location from status
            loc_match = re.search(r'(?:departed from|arrived at|is at)\s+([A-Z\s]+)', result.get("current_status", ""), re.I)
            if loc_match:
                result["current_location"] = loc_match.group(1).strip()

            # Extract last updated time
            updated_match = re.search(r'Last Updated:\s*(\d{1,2}\s+\w+\s+\d{4}\s+\d{2}:\d{2})', page_text)
            if updated_match:
                result["last_updated"] = updated_match.group(1)

            # Parse station-wise live status
            # The page format per station is:
            #   Station Name
            #   Day X  DD-Mon
            #   HH:MM (arrival)
            #   HH:MM (departure)
            #   Delay by X hr Y min  OR  Right Time
            lines = page_text.split('\n')

            # Skip UI elements
            skip_patterns = [
                'Check Live', 'Select', 'Submit', 'Free', 'Instant', 'Book',
                'Station', 'Date', 'Arrives', 'Departs', 'Late', 'IRCTC',
                'PNR', 'TRAIN', 'MORE', 'Login', 'Cancellation', 'Refund'
            ]

            current_station = {}

            for i, line in enumerate(lines):
                line = line.strip()

                # Skip empty lines and UI elements
                if not line or any(skip in line for skip in skip_patterns):
                    continue

                # Look for station names - Title Case words (e.g. "Kalyan Jn", "Lokmanyatilak T")
                if re.match(r'^[A-Z][a-z]+(?:\s+[A-Z][a-z]*)*(?:\s+(?:Jn|T|City))?\.?$', line) and len(line) > 3:
                    # Verify it's not a UI element
                    if line not in ['Right Time', 'On Time']:
                        if current_station and current_station.get('station'):
                            result["stations"].append(current_station)
                        current_station = {"station": line}
                        continue

                # Look for date (Day 1  20-Feb or similar)
                if re.match(r'^Day\s+\d+\s+\d{1,2}-\w{3}', line) and current_station:
                    current_station["date"] = line
                    continue

                # Look for time patterns (HH:MM)
                if re.match(r'^\d{2}:\d{2}$', line) and current_station:
                    if "arrival" not in current_station:
                        current_station["arrival"] = line
                    elif "departure" not in current_station:
                        current_station["departure"] = line
                    continue

                # Look for delay info - handle "Delay by X hr Y min" format
                if current_station:
                    if line in ['Right Time', 'On Time', 'RT']:
                        current_station["delay"] = 0
                        continue

                    delay_match = re.match(r'^Delay by\s+(?:(\d+)\s*hr?\s*)?(\d+)?\s*min?', line, re.I)
                    if delay_match:
                        hrs = int(delay_match.group(1)) if delay_match.group(1) else 0
                        mins = int(delay_match.group(2)) if delay_match.group(2) else 0
                        current_station["delay"] = hrs * 60 + mins
                        continue

                    # Fallback: simpler delay patterns like "45 min late"
                    simple_delay = re.match(r'^(\d+)\s*(min|hr)', line, re.I)
                    if simple_delay:
                        val = int(simple_delay.group(1))
                        if 'hr' in simple_delay.group(2).lower():
                            val *= 60
                        current_station["delay"] = val
                        continue

            if current_station and current_station.get('station'):
                result["stations"].append(current_station)

            # Filter out any remaining invalid stations
            valid_stations = []
            seen_stations = set()
            ad_cities = ['Lucknow', 'Pune', 'Bengaluru', 'Surat', 'Dharwad', 'Hyderabad',
                         'Chennai', 'Ahmedabad', 'Jaipur', 'Kolkata', 'Mumbai']

            for s in result["stations"]:
                station_name = s.get('station', '')
                # Skip invalid, duplicates, or ad cities
                if not station_name or len(station_name) <= 3:
                    continue
                if any(skip.lower() in station_name.lower() for skip in skip_patterns):
                    continue
                if station_name in seen_stations:
                    break  # Stop at first duplicate (likely ad section)
                if station_name in ad_cities and not s.get('arrival'):
                    break  # Stop at ad section (cities without times)

                # Calculate halt time from arrival and departure
                if s.get('arrival') and s.get('departure'):
                    try:
                        arr = datetime.strptime(s['arrival'], '%H:%M')
                        dep = datetime.strptime(s['departure'], '%H:%M')
                        diff = (dep - arr).seconds // 60
                        if diff > 0 and diff < 120:  # reasonable halt: 1 min to 2 hrs
                            s["halt"] = f"{diff} min"
                    except ValueError:
                        pass

                seen_stations.add(station_name)
                valid_stations.append(s)

            result["stations"] = valid_stations

            result["success"] = result["current_status"] is not None or len(result["stations"]) > 0

        except TimeoutException:
            result["error"] = "Page load timeout"
        except Exception as e:
            result["error"] = str(e)
        finally:
            self._close_driver()

        return result

    def search_trains(self, from_code: str, to_code: str) -> Dict[str, Any]:
        """
        Search trains between two stations.

        Args:
            from_code: Source station code
            to_code: Destination station code

        Returns:
            Dictionary with list of trains
        """
        result = {
            "from_station": from_code.upper(),
            "to_station": to_code.upper(),
            "trains": [],
            "source_website": "confirmtkt.com",
            "error": None,
            "success": False
        }

        try:
            self._setup_driver()
            url = f"{self.BASE_URL}/trains-between-stations/{from_code.upper()}/{to_code.upper()}"
            self.driver.get(url)
            time.sleep(4)

            page_text = self.driver.find_element(By.TAG_NAME, "body").text
            lines = page_text.split('\n')

            # Parse train list
            for i, line in enumerate(lines):
                # Look for train numbers
                train_match = re.match(r'^(\d{5})\s*[-–]?\s*([A-Z\s]+)', line)
                if train_match:
                    train_num = train_match.group(1)
                    train_name = train_match.group(2).strip()

                    train_info = {
                        "train_number": train_num,
                        "train_name": train_name,
                        "departure": None,
                        "arrival": None,
                        "duration": None,
                        "running_days": None
                    }

                    # Look for times in next few lines
                    for j in range(i+1, min(i+5, len(lines))):
                        next_line = lines[j].strip()
                        # Time pattern
                        time_match = re.findall(r'(\d{2}:\d{2})', next_line)
                        if time_match and len(time_match) >= 2:
                            train_info["departure"] = time_match[0]
                            train_info["arrival"] = time_match[1]
                        # Duration pattern
                        dur_match = re.search(r'(\d+h\s*\d+m|\d+:\d{2})', next_line)
                        if dur_match:
                            train_info["duration"] = dur_match.group(1)

                    result["trains"].append(train_info)

            result["success"] = len(result["trains"]) > 0

        except Exception as e:
            result["error"] = str(e)
        finally:
            self._close_driver()

        return result


# Convenience functions
def get_train_schedule(train_number: str) -> Dict[str, Any]:
    """Get detailed train schedule."""
    scraper = ConfirmTktScraper()
    return scraper.get_train_schedule(train_number)


def get_live_status(train_number: str, date: Optional[str] = None) -> Dict[str, Any]:
    """Get live running status of a train."""
    scraper = ConfirmTktScraper()
    return scraper.get_live_status(train_number, date)


def search_trains(from_code: str, to_code: str) -> Dict[str, Any]:
    """Search trains between stations."""
    scraper = ConfirmTktScraper()
    return scraper.search_trains(from_code, to_code)


def main():
    """Test the scraper."""
    import json
    import sys

    train = sys.argv[1] if len(sys.argv) > 1 else "12301"

    print(f"Fetching schedule for train {train}...")
    schedule = get_train_schedule(train)

    print("\n" + "=" * 70)
    print("  TRAIN SCHEDULE")
    print("=" * 70)

    if schedule.get("error"):
        print(f"\nError: {schedule['error']}")
    else:
        print(f"\nTrain: {schedule['train_number']} - {schedule.get('train_name', 'N/A')}")
        print(f"Route: {schedule.get('source', 'N/A')} → {schedule.get('destination', 'N/A')}")
        print(f"Timing: {schedule.get('departure', 'N/A')} → {schedule.get('arrival', 'N/A')}")
        print(f"Distance: {schedule.get('total_distance', 'N/A')}")
        print(f"Runs on: {', '.join(schedule.get('running_days', []))}")

        if schedule.get("stations"):
            print(f"\n{'─' * 90}")
            print(f"{'#':>3} {'Station':<25} {'Code':<6} {'Arr':>6} {'Dep':>6} {'Halt':>6} {'Dist':>10} {'Delay':>8}")
            print(f"{'─' * 90}")
            for stn in schedule["stations"]:
                delay = f"{stn['avg_delay_mins']} min" if stn.get('avg_delay_mins') else "-"
                print(f"{stn['sno']:>3} {stn['station_name'][:24]:<25} {stn['station_code']:<6} "
                      f"{stn.get('arrival') or '--':>6} {stn.get('departure') or '--':>6} "
                      f"{stn.get('halt_time') or '--':>6} {stn['distance_km']:>8.1f} km {delay:>8}")

    print("\n" + "=" * 70)

    if '--json' in sys.argv:
        print("\nJSON Output:")
        print(json.dumps(schedule, indent=2, default=str))


if __name__ == "__main__":
    main()
