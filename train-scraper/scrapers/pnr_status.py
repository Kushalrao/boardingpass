#!/usr/bin/env python3
"""
PNR Status Checker for Indian Railways.
Uses ConfirmTkt for reliable PNR status without CAPTCHA.
"""

import os
import time
import re
from typing import Dict, Any, Optional
from datetime import datetime
from pathlib import Path

# Load .env file if exists
env_file = Path(__file__).parent / '.env'
if env_file.exists():
    for line in env_file.read_text().strip().split('\n'):
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            os.environ.setdefault(key.strip(), value.strip())

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


class PNRStatusChecker:
    """Checks PNR status using ConfirmTkt (no CAPTCHA required)."""

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
        if self.driver:
            self.driver.quit()
            self.driver = None

    def check_pnr(self, pnr_number: str) -> Dict[str, Any]:
        """
        Check PNR status.

        Args:
            pnr_number: 10-digit PNR number

        Returns:
            Dictionary with PNR status information
        """
        # Validate PNR
        pnr_number = str(pnr_number).strip()
        if not pnr_number.isdigit() or len(pnr_number) != 10:
            return {
                "pnr": pnr_number,
                "error": "Invalid PNR. Must be 10 digits.",
                "success": False
            }

        result = {
            "pnr": pnr_number,
            "train_number": None,
            "train_name": None,
            "journey_date": None,
            "from_station": None,
            "to_station": None,
            "departure_time": None,
            "arrival_time": None,
            "boarding_point": None,
            "class": None,
            "quota": None,
            "passengers": [],
            "chart_status": None,
            "last_updated": datetime.now().isoformat(),
            "error": None,
            "success": False
        }

        try:
            self._setup_driver()

            # Use ConfirmTkt for PNR status
            url = f"https://www.confirmtkt.com/pnr-status/{pnr_number}"
            self.driver.get(url)

            # Wait for the page to fully load - look for key elements
            try:
                WebDriverWait(self.driver, 15).until(
                    lambda d: "Loading" not in d.find_element(By.TAG_NAME, "body").text
                    and len(d.find_element(By.TAG_NAME, "body").text) > 100
                )
            except TimeoutException:
                pass  # Continue with whatever we have

            time.sleep(2)  # Extra wait for JS rendering

            page_text = self.driver.find_element(By.TAG_NAME, "body").text

            # Check for errors/invalid PNR
            if "Flushed PNR" in page_text or "not yet generated" in page_text:
                result["error"] = "Flushed PNR or PNR not yet generated"
                result["status"] = "Invalid/Flushed"
                return result

            if "Invalid PNR" in page_text:
                result["error"] = "Invalid PNR Number"
                result["status"] = "Invalid"
                return result

            # Extract train info - look for pattern like "19702 - SAINIK EXPRESS" or "19702-SAINIK EXPRESS"
            # More specific pattern to avoid matching PNR digits
            train_patterns = [
                r'(\d{5})\s*[-–]\s*([A-Z][A-Z\s]+(?:EXP(?:RESS)?|MAIL|RAJ(?:DHANI)?|SF|SPECIAL|LOCAL|SUPERFAST)?)\s*(?:\n|$|Delhi|Mumbai|Chennai|Kolkata|[A-Z][a-z])',
                r'Train\s*(?:No\.?|Number)?\s*:?\s*(\d{5})\s*[-–]?\s*([A-Z][A-Za-z\s]+)',
                r'(\d{5})\s+([A-Z]{2,}(?:\s+[A-Z]+)*\s*(?:EXP(?:RESS)?|MAIL|SF|SPECIAL)?)',
            ]
            for pattern in train_patterns:
                train_match = re.search(pattern, page_text)
                if train_match:
                    result["train_number"] = train_match.group(1)
                    result["train_name"] = train_match.group(2).strip()
                    break

            # Extract date - look for patterns like "Tue, 27 Jan" or "27 Jan 2025"
            date_patterns = [
                r'(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*,?\s*(\d{1,2}\s+[A-Z][a-z]{2}(?:\s+\d{4})?)',
                r'(\d{1,2}\s+[A-Z][a-z]{2}\s+\d{4})',
                r'(\d{1,2}\s+[A-Z][a-z]+\s+\d{4})',
                r'(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})',
            ]
            for pattern in date_patterns:
                date_match = re.search(pattern, page_text)
                if date_match:
                    result["journey_date"] = date_match.group(1)
                    break

            # Extract stations - look for patterns like "Delhi Cantt - DEC, 00:07" on separate lines
            # Pattern: "Station Name - CODE, HH:MM" on consecutive lines
            station_line_pattern = r'([A-Za-z\s]+)\s*[-–]\s*([A-Z]{2,5}),?\s*(\d{2}:\d{2})'
            station_matches = re.findall(station_line_pattern, page_text)
            if len(station_matches) >= 2:
                # First match is source, second is destination
                result["from_station"] = f"{station_matches[0][0].strip()} ({station_matches[0][1]})"
                result["to_station"] = f"{station_matches[1][0].strip()} ({station_matches[1][1]})"
                result["departure_time"] = station_matches[0][2]
                result["arrival_time"] = station_matches[1][2]
            else:
                # Fallback to simpler patterns
                station_patterns = [
                    r'From[:\s]*([A-Z]{2,5})\s*(?:→|->|to|-)\s*To[:\s]*([A-Z]{2,5})',
                    r'\b([A-Z]{2,5})\s*(?:→|->|to)\s*([A-Z]{2,5})\b',
                ]
                for pattern in station_patterns:
                    station_match = re.search(pattern, page_text)
                    if station_match:
                        result["from_station"] = station_match.group(1)
                        result["to_station"] = station_match.group(2)
                        break

            # Extract class - look in context like "| SL |" or "Class: SL"
            class_match = re.search(r'(?:\|\s*|\bClass[:\s]*)(SL|3A|2A|1A|CC|2S|3E|EC|1AC|2AC|3AC|SLEEPER)\b', page_text, re.I)
            if class_match:
                result["class"] = class_match.group(1).upper()

            # Extract quota - look in context like "| GN |" or "Quota: GN"
            quota_match = re.search(r'(?:\|\s*|\bQuota[:\s]*)(GENERAL|GN|TATKAL|TQ|LADIES|LD|PREMIUM TATKAL|PT|GNWL|RLWL|PQWL)\b', page_text, re.I)
            if quota_match:
                quota = quota_match.group(1).upper()
                # Normalize quota names
                if quota in ['GNWL', 'RLWL', 'PQWL']:
                    result["quota"] = "GN"  # General quota with waitlist type
                else:
                    result["quota"] = quota

            # Extract chart status
            if "Chart Prepared" in page_text or "CHART PREPARED" in page_text:
                result["chart_status"] = "Prepared"
            elif "Chart Not Prepared" in page_text or "CHART NOT PREPARED" in page_text:
                result["chart_status"] = "Not Prepared"

            # Extract passenger details
            # Look for booking/current status patterns
            # Patterns: CNF/S5/23, WL54, RAC 12, CONFIRMED, GNWL 51, etc.

            # First, look for specific waitlist patterns like "GNWL 51" or "RLWL 23"
            wl_pattern = re.search(r'(GNWL|RLWL|PQWL|TQWL)\s*(\d+)', page_text, re.I)
            if wl_pattern:
                wl_type = wl_pattern.group(1).upper()
                wl_num = wl_pattern.group(2)
                result["passengers"].append({
                    "passenger": 1,
                    "booking_status": f"{wl_type} {wl_num}",
                    "current_status": f"Waitlist {wl_num} ({wl_type})",
                    "waitlist_type": wl_type,
                    "waitlist_number": int(wl_num)
                })

            # Look for confirmation chance
            chance_match = re.search(r'(\d+)%\s*(?:Chance|chance|probability|Confirmation)', page_text)
            if chance_match:
                result["confirmation_chance"] = f"{chance_match.group(1)}%"

            # Also look for booking status vs current status (e.g., "Booking: GNWL 138" vs "Current: GNWL 51")
            booking_match = re.search(r'(?:Booking|Book(?:ed)?)[:\s]*(GNWL|RLWL|PQWL|CNF|RAC)\s*(\d+)?', page_text, re.I)
            if booking_match and result["passengers"]:
                result["passengers"][0]["original_booking"] = f"{booking_match.group(1)} {booking_match.group(2) or ''}".strip()

            # Try to find passenger rows if no waitlist found
            if not result["passengers"]:
                lines = page_text.split('\n')
                seen_passengers = set()  # Track unique (coach, berth) combos

                for i, line in enumerate(lines):
                    line = line.strip()

                    # Skip UI/navigation text that might contain status keywords
                    skip_keywords = ['watch', 'click', 'button', 'link', 'menu', 'submit', 'book ticket']
                    if any(kw in line.lower() for kw in skip_keywords):
                        continue

                    # Look for CNF with coach and berth: "CNF S5 9" or "CNF/S5/9"
                    cnf_match = re.search(
                        r'\bCNF\s*[/:]?\s*([A-Z]\d+)\s*[/:]?\s*(\d+)\b',
                        line, re.I
                    )
                    if cnf_match:
                        coach = cnf_match.group(1).upper()
                        berth = cnf_match.group(2)
                        unique_key = ('CNF', coach, berth)
                        if unique_key not in seen_passengers:
                            seen_passengers.add(unique_key)
                            passenger_num = len(result["passengers"]) + 1
                            result["passengers"].append({
                                "passenger": passenger_num,
                                "booking_status": "Confirmed",
                                "current_status": f"Confirmed ({coach}/{berth})",
                                "coach": coach,
                                "berth": berth
                            })
                        continue

                    # Look for RAC with number: "RAC 12" or "RAC/12"
                    rac_match = re.search(r'\bRAC\s*[/:]?\s*(\d+)\b', line, re.I)
                    if rac_match:
                        rac_num = rac_match.group(1)
                        unique_key = ('RAC', rac_num)
                        if unique_key not in seen_passengers:
                            seen_passengers.add(unique_key)
                            passenger_num = len(result["passengers"]) + 1
                            result["passengers"].append({
                                "passenger": passenger_num,
                                "booking_status": f"RAC{rac_num}",
                                "current_status": f"RAC {rac_num}"
                            })
                        continue

                    # Look for WL with number: "WL 54" or "GNWL 51"
                    wl_match = re.search(r'\b(GNWL|RLWL|PQWL|WL)\s*[/:]?\s*(\d+)\b', line, re.I)
                    if wl_match:
                        wl_type = wl_match.group(1).upper()
                        wl_num = wl_match.group(2)
                        unique_key = (wl_type, wl_num)
                        if unique_key not in seen_passengers:
                            seen_passengers.add(unique_key)
                            passenger_num = len(result["passengers"]) + 1
                            result["passengers"].append({
                                "passenger": passenger_num,
                                "booking_status": f"{wl_type} {wl_num}",
                                "current_status": f"Waitlist {wl_num} ({wl_type})"
                            })
                        continue

                    # Look for CANCELLED
                    if re.search(r'\b(CAN|CANCELLED)\b', line, re.I):
                        unique_key = ('CANCELLED', i)  # Use line index for uniqueness
                        if unique_key not in seen_passengers:
                            seen_passengers.add(unique_key)
                            passenger_num = len(result["passengers"]) + 1
                            result["passengers"].append({
                                "passenger": passenger_num,
                                "booking_status": "Cancelled",
                                "current_status": "Cancelled"
                            })

            # If no passengers found, try alternative extraction
            if not result["passengers"]:
                # Look for CNF with coach/berth pattern like "CNF S5 9" and deduplicate
                cnf_matches = re.findall(r'\bCNF\s+([A-Z]\d+)\s+(\d+)', page_text, re.I)
                unique_cnf = set(cnf_matches)  # Deduplicate

                wl_matches = re.findall(r'\bWL\s*(\d+)', page_text, re.I)
                unique_wl = list(set(wl_matches))  # Deduplicate

                rac_matches = re.findall(r'\bRAC\s*(\d+)', page_text, re.I)
                unique_rac = list(set(rac_matches))  # Deduplicate

                if unique_cnf:
                    for i, (coach, berth) in enumerate(unique_cnf):
                        result["passengers"].append({
                            "passenger": i + 1,
                            "booking_status": "Confirmed",
                            "current_status": f"Confirmed ({coach}/{berth})",
                            "coach": coach,
                            "berth": berth
                        })
                elif unique_wl:
                    for i, wl in enumerate(unique_wl):
                        result["passengers"].append({
                            "passenger": i + 1,
                            "booking_status": f"WL{wl}",
                            "current_status": f"Waitlist {wl}"
                        })
                elif unique_rac:
                    for i, rac in enumerate(unique_rac):
                        result["passengers"].append({
                            "passenger": i + 1,
                            "booking_status": f"RAC{rac}",
                            "current_status": f"RAC {rac}"
                        })

            # Determine overall status
            if result["passengers"]:
                statuses = [p["current_status"].lower() for p in result["passengers"]]
                if all('confirm' in s for s in statuses):
                    result["overall_status"] = "✅ Confirmed"
                elif any('confirm' in s for s in statuses):
                    result["overall_status"] = "⚠️ Partially Confirmed"
                elif any('rac' in s for s in statuses):
                    result["overall_status"] = "🔶 RAC"
                elif any('cancel' in s for s in statuses):
                    result["overall_status"] = "❌ Cancelled"
                else:
                    result["overall_status"] = "⏳ Waitlist"

            result["success"] = True
            result["source"] = "confirmtkt.com"

        except TimeoutException:
            result["error"] = "Page load timeout"
        except Exception as e:
            result["error"] = str(e)
        finally:
            self._close_driver()

        return result


def check_pnr(pnr_number: str) -> Dict[str, Any]:
    """Convenience function to check PNR status."""
    checker = PNRStatusChecker()
    return checker.check_pnr(pnr_number)


def main():
    import sys
    import json

    if len(sys.argv) < 2:
        print("=" * 50)
        print("  PNR Status Checker - Indian Railways")
        print("=" * 50)
        print("\nUsage: python pnr_status.py <10-digit-PNR>")
        print("\nExample:")
        print("  python pnr_status.py 2612345678")
        print("\nNote: PNR can be found on the top-left corner of your ticket")
        sys.exit(1)

    pnr = sys.argv[1]

    print(f"Checking PNR: {pnr}")
    print("Please wait...")

    result = check_pnr(pnr)

    # Pretty print
    print("\n" + "=" * 55)
    print("  PNR STATUS RESULT")
    print("=" * 55)

    if result.get("error"):
        print(f"\n❌ {result['error']}")
    else:
        print(f"\n📋 PNR: {result['pnr']}")

        if result.get('train_number'):
            print(f"🚂 Train: {result['train_number']} - {result.get('train_name', 'N/A')}")

        if result.get('journey_date'):
            print(f"📅 Date: {result['journey_date']}")

        if result.get('from_station') and result.get('to_station'):
            route_str = f"📍 Route: {result['from_station']} → {result['to_station']}"
            if result.get('departure_time') and result.get('arrival_time'):
                route_str += f" ({result['departure_time']} - {result['arrival_time']})"
            print(route_str)

        if result.get('class'):
            print(f"🎫 Class: {result['class']}")

        if result.get('quota'):
            print(f"📊 Quota: {result['quota']}")

        if result.get('chart_status'):
            print(f"📈 Chart: {result['chart_status']}")

        if result.get('overall_status'):
            print(f"\n{'─' * 40}")
            print(f"Status: {result['overall_status']}")
            print(f"{'─' * 40}")

        if result.get("passengers"):
            print(f"\n👥 Passengers ({len(result['passengers'])}):")
            for p in result["passengers"]:
                coach_info = ""
                if p.get('coach') and p.get('berth'):
                    coach_info = f" - Coach {p['coach']}, Berth {p['berth']}"
                print(f"   Passenger {p['passenger']}: {p['current_status']}{coach_info}")

    print("\n" + "=" * 55)

    if '--json' in sys.argv:
        print("\nJSON Output:")
        print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
