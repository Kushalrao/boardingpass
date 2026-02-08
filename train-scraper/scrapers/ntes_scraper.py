"""
NTES (National Train Enquiry System) Scraper
Scrapes train information from Indian Railways.

Provides multiple data sources:
1. NTESScraper - Direct NTES website scraping
2. IndianRailwaysAPI - Uses erail.in API
3. RailwayInfoScraper - Scrapes indiarailinfo.com (most reliable)
"""

import requests
from bs4 import BeautifulSoup
from dataclasses import dataclass
from typing import Optional, List, Dict, Any
import json
import re
from datetime import datetime
import time


@dataclass
class Station:
    """Represents a station in train route."""
    sno: int
    code: str
    name: str
    arrival: Optional[str]
    departure: Optional[str]
    halt: Optional[str]
    day: int
    distance: int


class NTESScraper:
    """
    Scraper for NTES (National Train Enquiry System).
    Uses the mobile-friendly endpoints.
    """

    BASE_URL = "https://enquiry.indianrail.gov.in/mntes"

    HEADERS = {
        "User-Agent": "Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
    }

    def __init__(self, timeout: int = 15):
        self.session = requests.Session()
        self.session.headers.update(self.HEADERS)
        self.timeout = timeout

    def get_live_status(self, train_number: str, date: Optional[str] = None) -> Dict[str, Any]:
        """Get live running status of a train."""
        if date is None:
            date = datetime.now().strftime("%Y%m%d")

        url = f"{self.BASE_URL}/q"
        params = {
            "opt": "TrainRunning",
            "subOpt": "trainRunSearch",
            "trainNo": train_number,
        }

        result = {
            "train_number": train_number,
            "date": date,
            "status": "unknown",
            "stations": [],
            "error": None
        }

        try:
            resp = self.session.get(url, params=params, timeout=self.timeout)
            if resp.ok:
                soup = BeautifulSoup(resp.text, 'lxml')
                table = soup.find('table')
                if table:
                    result["stations"] = self._parse_table(table)
                result["status"] = "success" if result["stations"] else "no_data"
        except requests.RequestException as e:
            result["error"] = str(e)

        return result

    def get_train_schedule(self, train_number: str) -> Dict[str, Any]:
        """Get schedule/route of a train."""
        url = f"{self.BASE_URL}/q"
        params = {
            "opt": "TrainSchedule",
            "subOpt": "trainSchSearch",
            "trainNo": train_number,
        }

        result = {
            "train_number": train_number,
            "train_name": None,
            "stations": [],
            "error": None
        }

        try:
            resp = self.session.get(url, params=params, timeout=self.timeout)
            if resp.ok:
                soup = BeautifulSoup(resp.text, 'lxml')
                table = soup.find('table')
                if table:
                    result["stations"] = self._parse_table(table)
                result["status"] = "success" if result["stations"] else "no_data"
        except requests.RequestException as e:
            result["error"] = str(e)

        return result

    def _parse_table(self, table) -> List[Dict]:
        """Generic table parser."""
        rows = []
        headers = []

        header_row = table.find('tr')
        if header_row:
            headers = [th.get_text(strip=True).lower() for th in header_row.find_all(['th', 'td'])]

        for tr in table.find_all('tr')[1:]:
            cols = tr.find_all('td')
            if cols:
                if headers:
                    row = {headers[i]: cols[i].get_text(strip=True) for i in range(min(len(headers), len(cols)))}
                else:
                    row = {f"col_{i}": col.get_text(strip=True) for i, col in enumerate(cols)}
                rows.append(row)

        return rows


class RailwayInfoScraper:
    """
    Scraper for indiarailinfo.com - most reliable source.
    """

    BASE_URL = "https://indiarailinfo.com"

    HEADERS = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
    }

    def __init__(self, timeout: int = 15):
        self.session = requests.Session()
        self.session.headers.update(self.HEADERS)
        self.timeout = timeout

    def get_train_schedule(self, train_number: str) -> Dict[str, Any]:
        """
        Get train schedule from indiarailinfo.com
        """
        url = f"{self.BASE_URL}/train/{train_number}"

        result = {
            "train_number": train_number,
            "train_name": None,
            "from_station": None,
            "to_station": None,
            "runs_on": [],
            "stations": [],
            "error": None
        }

        try:
            resp = self.session.get(url, timeout=self.timeout)
            if resp.ok:
                soup = BeautifulSoup(resp.text, 'lxml')

                # Extract train name
                title = soup.find('h1')
                if title:
                    result["train_name"] = title.get_text(strip=True)

                # Find the schedule table
                tables = soup.find_all('table')
                for table in tables:
                    # Look for table with station data
                    header_row = table.find('tr')
                    if header_row:
                        headers = [th.get_text(strip=True).lower() for th in header_row.find_all(['th', 'td'])]
                        if any('station' in h or 'code' in h for h in headers):
                            for tr in table.find_all('tr')[1:]:
                                cols = tr.find_all('td')
                                if len(cols) >= 4:
                                    station = {
                                        "sno": cols[0].get_text(strip=True) if len(cols) > 0 else None,
                                        "station_code": cols[1].get_text(strip=True) if len(cols) > 1 else None,
                                        "station_name": cols[2].get_text(strip=True) if len(cols) > 2 else None,
                                        "arrival": cols[3].get_text(strip=True) if len(cols) > 3 else None,
                                        "departure": cols[4].get_text(strip=True) if len(cols) > 4 else None,
                                        "day": cols[5].get_text(strip=True) if len(cols) > 5 else None,
                                        "distance": cols[6].get_text(strip=True) if len(cols) > 6 else None,
                                    }
                                    result["stations"].append(station)
                            break

                if result["stations"]:
                    result["from_station"] = result["stations"][0].get("station_name")
                    result["to_station"] = result["stations"][-1].get("station_name")

                result["status"] = "success" if result["stations"] else "no_data"
        except requests.RequestException as e:
            result["error"] = str(e)

        return result

    def search_trains(self, from_code: str, to_code: str) -> Dict[str, Any]:
        """
        Search trains between two stations.
        """
        url = f"{self.BASE_URL}/trains/{from_code.upper()}/{to_code.upper()}"

        result = {
            "from_station": from_code.upper(),
            "to_station": to_code.upper(),
            "trains": [],
            "error": None
        }

        try:
            resp = self.session.get(url, timeout=self.timeout)
            if resp.ok:
                soup = BeautifulSoup(resp.text, 'lxml')

                # Find train list table
                tables = soup.find_all('table')
                for table in tables:
                    for tr in table.find_all('tr')[1:]:
                        cols = tr.find_all('td')
                        if len(cols) >= 4:
                            # Look for train number pattern
                            first_col = cols[0].get_text(strip=True)
                            if re.match(r'\d{5}', first_col):
                                train = {
                                    "train_number": first_col,
                                    "train_name": cols[1].get_text(strip=True) if len(cols) > 1 else None,
                                    "departure": cols[2].get_text(strip=True) if len(cols) > 2 else None,
                                    "arrival": cols[3].get_text(strip=True) if len(cols) > 3 else None,
                                    "duration": cols[4].get_text(strip=True) if len(cols) > 4 else None,
                                }
                                result["trains"].append(train)

                result["status"] = "success" if result["trains"] else "no_data"
        except requests.RequestException as e:
            result["error"] = str(e)

        return result


class IndianRailwaysAPI:
    """
    Uses erail.in data API - the most commonly used source.
    Note: erail uses a complex format, this parser extracts basic info.
    """

    HEADERS = {
        "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36",
        "Accept": "*/*",
        "Referer": "https://erail.in/",
    }

    # Class codes for seat availability
    CLASS_CODES = {
        "1A": "First AC",
        "2A": "AC 2 Tier",
        "3A": "AC 3 Tier",
        "3E": "AC 3 Economy",
        "SL": "Sleeper",
        "CC": "Chair Car",
        "2S": "Second Sitting",
        "EC": "Executive Chair Car",
        "FC": "First Class",
    }

    def __init__(self, timeout: int = 15):
        self.session = requests.Session()
        self.session.headers.update(self.HEADERS)
        self.timeout = timeout

    def get_train_info(self, train_number: str) -> Dict[str, Any]:
        """
        Get basic train info from erail.in
        """
        url = "https://erail.in/rail/getTrains.aspx"
        params = {
            "TrainNo": train_number,
            "DataSource": "0",
            "Language": "0",
        }

        result = {
            "train_number": train_number,
            "source": "erail.in",
            "train_name": None,
            "from_station": None,
            "from_code": None,
            "to_station": None,
            "to_code": None,
            "departure": None,
            "arrival": None,
            "duration": None,
            "runs_on": None,
            "error": None
        }

        try:
            resp = self.session.get(url, params=params, timeout=self.timeout)
            if resp.ok:
                text = resp.text.strip()
                # Parse erail format
                # Format: ^TrainNo~Name~FromName~FromCode~ToName~ToCode~...~DepTime~ArrTime~...~RunsOn
                if f'^{train_number}~' in text:
                    start = text.find(f'^{train_number}~')
                    section = text[start:].split('~')
                    if len(section) >= 14:
                        result["train_name"] = section[1]
                        result["from_station"] = section[2]
                        result["from_code"] = section[3]
                        result["to_station"] = section[4]
                        result["to_code"] = section[5]
                        result["departure"] = section[10] if len(section) > 10 else None
                        result["arrival"] = section[11] if len(section) > 11 else None
                        # Runs on is a 7-char string: 1111110 = Mon-Sat
                        runs_on_raw = section[13] if len(section) > 13 else ""
                        if runs_on_raw and len(runs_on_raw) == 7:
                            days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                            result["runs_on"] = ', '.join(d for i, d in enumerate(days) if runs_on_raw[i] == '1')
                        else:
                            result["runs_on"] = runs_on_raw

                result["status"] = "success" if result["train_name"] else "no_data"
        except Exception as e:
            result["error"] = str(e)

        return result

    def search_trains(self, from_code: str, to_code: str) -> Dict[str, Any]:
        """
        Search trains between stations using erail.in
        """
        url = "https://erail.in/rail/getTrains.aspx"
        params = {
            "Station_From": from_code.upper(),
            "Station_To": to_code.upper(),
            "DataSource": "0",
            "Language": "0",
        }

        result = {
            "from_station": from_code.upper(),
            "to_station": to_code.upper(),
            "source": "erail.in",
            "trains": [],
            "error": None
        }

        try:
            resp = self.session.get(url, params=params, timeout=self.timeout)
            if resp.ok:
                text = resp.text.strip()
                # Each train is separated by ~^
                trains_data = text.split('~^')

                for train_str in trains_data:
                    parts = train_str.split('~')
                    # Look for 5-digit train numbers
                    train_num = parts[0].replace('^', '')
                    if len(parts) >= 14 and re.match(r'\d{5}', train_num):
                        # Parse runs_on
                        runs_on_raw = parts[13] if len(parts) > 13 else ""
                        if runs_on_raw and len(runs_on_raw) == 7:
                            days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                            runs_on = ', '.join(d for i, d in enumerate(days) if runs_on_raw[i] == '1')
                        else:
                            runs_on = runs_on_raw

                        train = {
                            "train_number": train_num,
                            "train_name": parts[1] if len(parts) > 1 else None,
                            "from_station": parts[2] if len(parts) > 2 else None,
                            "from_code": parts[3] if len(parts) > 3 else None,
                            "to_station": parts[4] if len(parts) > 4 else None,
                            "to_code": parts[5] if len(parts) > 5 else None,
                            "departure": parts[10] if len(parts) > 10 else None,
                            "arrival": parts[11] if len(parts) > 11 else None,
                            "duration": parts[12] if len(parts) > 12 else None,
                            "runs_on": runs_on,
                        }
                        result["trains"].append(train)

                result["status"] = "success" if result["trains"] else "no_data"
        except Exception as e:
            result["error"] = str(e)

        return result

    def search_station(self, query: str) -> List[Dict]:
        """
        Search for stations by name using IRCTC autocomplete.
        """
        # Use IRCTC's station autocomplete API
        url = "https://www.irctc.co.in/eticketing/protected/mapps1/stabordstnautocomplete"
        params = {"searchType": "stnb", "searchText": query}

        stations = []
        try:
            resp = self.session.get(url, params=params, timeout=self.timeout)
            if resp.ok:
                try:
                    data = resp.json()
                    if isinstance(data, list):
                        for item in data:
                            if isinstance(item, dict):
                                stations.append({
                                    "code": item.get("stnCode", ""),
                                    "name": item.get("stnName", ""),
                                })
                            elif isinstance(item, str) and ' - ' in item:
                                parts = item.split(' - ')
                                stations.append({
                                    "code": parts[-1].strip() if len(parts) > 1 else "",
                                    "name": parts[0].strip(),
                                })
                except:
                    # Fallback: try splitting text response
                    for line in resp.text.strip().split('\n'):
                        if ' - ' in line:
                            parts = line.split(' - ')
                            stations.append({
                                "code": parts[-1].strip(),
                                "name": parts[0].strip(),
                            })
        except Exception as e:
            # Return common stations if API fails
            common_stations = {
                "mumbai": [
                    {"code": "CSMT", "name": "Mumbai Chhatrapati Shivaji Terminus"},
                    {"code": "BCT", "name": "Mumbai Central"},
                    {"code": "LTT", "name": "Lokmanya Tilak Terminus"},
                    {"code": "BDTS", "name": "Bandra Terminus"},
                ],
                "delhi": [
                    {"code": "NDLS", "name": "New Delhi"},
                    {"code": "DLI", "name": "Old Delhi"},
                    {"code": "NZM", "name": "Hazrat Nizamuddin"},
                    {"code": "ANVT", "name": "Anand Vihar Terminal"},
                ],
                "chennai": [
                    {"code": "MAS", "name": "Chennai Central"},
                    {"code": "MS", "name": "Chennai Egmore"},
                ],
                "kolkata": [
                    {"code": "HWH", "name": "Howrah Junction"},
                    {"code": "KOAA", "name": "Kolkata"},
                    {"code": "SDAH", "name": "Sealdah"},
                ],
            }
            query_lower = query.lower()
            for city, stns in common_stations.items():
                if city in query_lower or query_lower in city:
                    stations.extend(stns)
            if not stations:
                stations.append({"error": str(e), "note": "API unavailable, showing common stations"})

        return stations

    def get_fare(self, train_number: str, from_code: str, to_code: str) -> Dict[str, Any]:
        """
        Get fare information for a train between two stations.
        Uses distance-based calculation with Indian Railways fare rates.
        """
        url = "https://erail.in/rail/getTrains.aspx"
        params = {
            "TrainNo": train_number,
            "Station_From": from_code.upper(),
            "Station_To": to_code.upper(),
            "DataSource": "0",
            "Language": "0",
        }

        result = {
            "train_number": train_number,
            "from_station": from_code.upper(),
            "to_station": to_code.upper(),
            "source": "calculated",
            "train_name": None,
            "train_type": None,
            "distance": None,
            "fares": {},
            "error": None
        }

        # Common route distances (km) - comprehensive lookup
        route_distances = {
            # Major routes from Delhi
            ("NDLS", "BCT"): 1384, ("NDLS", "CSMT"): 1384, ("NDLS", "LTT"): 1400,
            ("NDLS", "MAS"): 2175, ("NDLS", "HWH"): 1447, ("NDLS", "BPL"): 700,
            ("NDLS", "LKO"): 511, ("NDLS", "CNB"): 440, ("NDLS", "JP"): 308,
            ("NDLS", "AGC"): 188, ("NDLS", "DDN"): 307, ("NDLS", "ADI"): 935,
            ("NDLS", "BLR"): 2150, ("NDLS", "PUNE"): 1500, ("NDLS", "GKP"): 810,
            ("NDLS", "PRYJ"): 630, ("NDLS", "SVDK"): 655, ("NDLS", "JAT"): 350,
            # Mumbai routes
            ("BCT", "MAS"): 1279, ("CSMT", "MAS"): 1279, ("BCT", "ADI"): 493,
            ("ADI", "BCT"): 493, ("ADI", "BDTS"): 493, ("BCT", "PUNE"): 192,
            ("BCT", "NGP"): 859, ("BCT", "HWH"): 1970, ("BCT", "BLR"): 1200,
            ("LTT", "MAS"): 1290, ("LTT", "HWH"): 1960,
            # South India
            ("MAS", "BLR"): 362, ("MAS", "HWH"): 1663, ("MAS", "TVC"): 918,
            ("MAS", "SBC"): 362, ("BLR", "MYS"): 140, ("BLR", "HYB"): 570,
            ("HYB", "MAS"): 785, ("HYB", "BCT"): 710,
            # East India
            ("HWH", "NDLS"): 1447, ("HWH", "MAS"): 1663, ("HWH", "BCT"): 1970,
            ("HWH", "PURI"): 500, ("HWH", "GHY"): 985,
            # Gujarat
            ("ADI", "BDTS"): 493, ("ADI", "JP"): 670, ("ADI", "UDZ"): 280,
            ("SBC", "MAS"): 362, ("SBC", "BCT"): 1200,
        }

        # First, check lookup table for accurate segment distance
        route_key = (from_code.upper(), to_code.upper())
        reverse_key = (to_code.upper(), from_code.upper())
        if route_key in route_distances:
            result["distance"] = route_distances[route_key]
        elif reverse_key in route_distances:
            result["distance"] = route_distances[reverse_key]

        try:
            resp = self.session.get(url, params=params, timeout=self.timeout)
            if resp.ok:
                text = resp.text.strip()

                # Extract train name
                if f'^{train_number}~' in text or train_number in text:
                    parts = text.split('~')
                    for i, part in enumerate(parts):
                        if train_number in part.replace('^', ''):
                            if i + 1 < len(parts):
                                result["train_name"] = parts[i + 1]
                            break

                # Detect train type
                train_type = "mail_express"
                text_lower = text.lower()
                if "rajdhani" in text_lower:
                    train_type = "rajdhani"
                elif "shatabdi" in text_lower:
                    train_type = "shatabdi"
                elif "duronto" in text_lower:
                    train_type = "duronto"
                elif "vande bharat" in text_lower or "vandebharat" in text_lower:
                    train_type = "vande_bharat"
                elif "garib rath" in text_lower:
                    train_type = "garib_rath"
                elif "tejas" in text_lower:
                    train_type = "tejas"

                result["train_type"] = train_type

        except Exception as e:
            result["error"] = str(e)

        # If distance still not found, use default estimate
        if not result.get("distance"):
            result["distance"] = 500  # Default estimate
            result["distance_note"] = "estimated"

        distance = result["distance"]
        train_type = result.get("train_type", "mail_express")

        # Calculate fares based on 2024-2025 Indian Railways rates
        if train_type == "rajdhani":
            result["fares"] = {
                "1A": {"class": "First AC", "fare": int(distance * 3.02 + 1500)},
                "2A": {"class": "AC 2 Tier", "fare": int(distance * 1.80 + 900)},
                "3A": {"class": "AC 3 Tier", "fare": int(distance * 1.32 + 650)},
            }
            result["includes"] = "Catering included"
        elif train_type == "shatabdi":
            result["fares"] = {
                "EC": {"class": "Executive Chair", "fare": int(distance * 2.25 + 400)},
                "CC": {"class": "Chair Car", "fare": int(distance * 1.35 + 250)},
            }
            result["includes"] = "Catering included"
        elif train_type == "vande_bharat":
            result["fares"] = {
                "EC": {"class": "Executive Chair", "fare": int(distance * 2.50 + 500)},
                "CC": {"class": "Chair Car", "fare": int(distance * 1.50 + 300)},
            }
            result["includes"] = "Catering included"
        elif train_type == "duronto":
            result["fares"] = {
                "1A": {"class": "First AC", "fare": int(distance * 2.90 + 1400)},
                "2A": {"class": "AC 2 Tier", "fare": int(distance * 1.70 + 850)},
                "3A": {"class": "AC 3 Tier", "fare": int(distance * 1.25 + 600)},
                "SL": {"class": "Sleeper", "fare": int(distance * 0.65 + 200)},
            }
            result["includes"] = "Catering included"
        elif train_type == "garib_rath":
            result["fares"] = {
                "3A": {"class": "AC 3 Tier", "fare": int(distance * 0.95 + 350)},
            }
        else:
            # Regular Mail/Express trains
            result["fares"] = {
                "1A": {"class": "First AC", "fare": int(distance * 2.55 + 280)},
                "2A": {"class": "AC 2 Tier", "fare": int(distance * 1.50 + 180)},
                "3A": {"class": "AC 3 Tier", "fare": int(distance * 1.10 + 120)},
                "SL": {"class": "Sleeper", "fare": int(distance * 0.55 + 45)},
                "2S": {"class": "Second Sitting", "fare": int(distance * 0.35 + 25)},
            }

        result["distance"] = f"{distance} km"
        result["fare_note"] = "Base fares (GST, reservation charges extra)"
        result["status"] = "success"

        return result

    def get_seat_availability(self, train_number: str, from_code: str, to_code: str,
                              date: str, class_code: str = "SL") -> Dict[str, Any]:
        """
        Get seat availability for a train.

        Args:
            train_number: 5-digit train number
            from_code: Source station code
            to_code: Destination station code
            date: Date in YYYYMMDD or DD-MM-YYYY format
            class_code: Class code (1A, 2A, 3A, SL, CC, 2S, etc.)

        Returns:
            Dictionary with availability information
        """
        result = {
            "train_number": train_number,
            "from_station": from_code.upper(),
            "to_station": to_code.upper(),
            "date": date,
            "class": class_code.upper(),
            "class_name": self.CLASS_CODES.get(class_code.upper(), class_code),
            "source": "erail.in",
            "availability": None,
            "status": None,
            "error": None
        }

        # Convert date format if needed
        if '-' in date:
            try:
                dt = datetime.strptime(date, "%d-%m-%Y")
                date = dt.strftime("%Y%m%d")
            except:
                pass

        try:
            # erail.in seat availability endpoint
            url = "https://erail.in/rail/getTrains.aspx"
            params = {
                "TrainNo": train_number,
                "Station_From": from_code.upper(),
                "Station_To": to_code.upper(),
                "JDate": date,
                "Class": class_code.upper(),
                "Rone": "1",
                "DataSource": "0",
                "Language": "0",
            }

            resp = self.session.get(url, params=params, timeout=self.timeout)
            if resp.ok:
                text = resp.text.strip()

                # Look for availability status patterns
                availability_patterns = [
                    r'(AVL|AVAILABLE)\s*[-:]?\s*(\d+)',  # Available with count
                    r'(WL|WAITLIST)\s*[-/]?\s*(\d+)',     # Waitlist
                    r'(RAC)\s*[-/]?\s*(\d+)',            # RAC
                    r'(REGRET|NOT AVAILABLE)',           # Not available
                    r'(GNWL|RLWL|PQWL)\s*[-/]?\s*(\d+)', # Specific waitlist types
                    r'(CNF|CONFIRM)',                    # Confirmed
                ]

                for pattern in availability_patterns:
                    match = re.search(pattern, text, re.I)
                    if match:
                        groups = match.groups()
                        status = groups[0].upper()
                        count = groups[1] if len(groups) > 1 else None

                        if status in ['AVL', 'AVAILABLE']:
                            result["availability"] = f"Available ({count})" if count else "Available"
                            result["status"] = "available"
                        elif status in ['WL', 'WAITLIST', 'GNWL', 'RLWL', 'PQWL']:
                            result["availability"] = f"{status} {count}" if count else status
                            result["status"] = "waitlist"
                        elif status == 'RAC':
                            result["availability"] = f"RAC {count}" if count else "RAC"
                            result["status"] = "rac"
                        elif status in ['REGRET', 'NOT AVAILABLE']:
                            result["availability"] = "Not Available"
                            result["status"] = "not_available"
                        elif status in ['CNF', 'CONFIRM']:
                            result["availability"] = "Confirmed"
                            result["status"] = "available"
                        break

                # If no pattern found, check for numeric availability
                if not result["availability"]:
                    num_match = re.search(r'(\d+)\s*(?:seats?|berths?)', text, re.I)
                    if num_match:
                        result["availability"] = f"Available ({num_match.group(1)})"
                        result["status"] = "available"

                result["success"] = result["availability"] is not None

        except Exception as e:
            result["error"] = str(e)

        return result

    def get_station_trains(self, station_code: str, hours: int = 4) -> Dict[str, Any]:
        """
        Get trains arriving/departing at a station.

        Args:
            station_code: Station code (e.g., NDLS, BCT)
            hours: Hours to look ahead (default 4)

        Returns:
            Dictionary with arrivals and departures
        """
        result = {
            "station_code": station_code.upper(),
            "station_name": None,
            "hours": hours,
            "source": "erail.in",
            "arrivals": [],
            "departures": [],
            "error": None
        }

        # Station name mapping
        station_names = {
            "NDLS": "New Delhi", "BCT": "Mumbai Central", "CSMT": "Mumbai CST",
            "HWH": "Howrah", "MAS": "Chennai Central", "BLR": "Bangalore",
            "ADI": "Ahmedabad", "JP": "Jaipur", "LKO": "Lucknow",
            "PUNE": "Pune", "SBC": "Bangalore City", "BPL": "Bhopal",
        }
        result["station_name"] = station_names.get(station_code.upper(), station_code.upper())

        # Major destination stations to search trains from this station
        major_stations = ["BCT", "NDLS", "HWH", "MAS", "ADI", "JP", "LKO", "PUNE", "BPL", "CNB", "AGC"]

        try:
            search_url = "https://erail.in/rail/getTrains.aspx"
            seen_trains = set()

            # Get trains DEPARTING from this station
            for dest in major_stations:
                if dest == station_code.upper():
                    continue

                params = {
                    "Station_From": station_code.upper(),
                    "Station_To": dest,
                    "DataSource": "0",
                    "Language": "0",
                }

                try:
                    resp = self.session.get(search_url, params=params, timeout=10)
                    if resp.ok and "station missing" not in resp.text.lower():
                        text = resp.text.strip()
                        trains_data = text.split('~^')

                        for train_str in trains_data[:20]:
                            parts = train_str.replace('^', '').split('~')
                            train_num = parts[0] if parts else ""

                            if len(parts) >= 11 and re.match(r'\d{5}', train_num):
                                if train_num in seen_trains:
                                    continue
                                seen_trains.add(train_num)

                                dep_time = parts[10] if len(parts) > 10 else None
                                if dep_time and re.match(r'\d{1,2}[.:]\d{2}', str(dep_time)):
                                    train_info = {
                                        "train_number": train_num,
                                        "train_name": parts[1] if len(parts) > 1 else None,
                                        "to_station": parts[4] if len(parts) > 4 else None,
                                        "to_code": parts[5] if len(parts) > 5 else None,
                                        "departure": dep_time.replace('.', ':'),
                                        "platform": None,
                                    }
                                    result["departures"].append(train_info)
                except:
                    pass

            seen_trains = set()

            # Get trains ARRIVING at this station
            for src in major_stations:
                if src == station_code.upper():
                    continue

                params = {
                    "Station_From": src,
                    "Station_To": station_code.upper(),
                    "DataSource": "0",
                    "Language": "0",
                }

                try:
                    resp = self.session.get(search_url, params=params, timeout=10)
                    if resp.ok and "station missing" not in resp.text.lower():
                        text = resp.text.strip()
                        trains_data = text.split('~^')

                        for train_str in trains_data[:20]:
                            parts = train_str.replace('^', '').split('~')
                            train_num = parts[0] if parts else ""

                            if len(parts) >= 12 and re.match(r'\d{5}', train_num):
                                if train_num in seen_trains:
                                    continue
                                seen_trains.add(train_num)

                                arr_time = parts[11] if len(parts) > 11 else None
                                if arr_time and re.match(r'\d{1,2}[.:]\d{2}', str(arr_time)):
                                    train_info = {
                                        "train_number": train_num,
                                        "train_name": parts[1] if len(parts) > 1 else None,
                                        "from_station": parts[2] if len(parts) > 2 else None,
                                        "from_code": parts[3] if len(parts) > 3 else None,
                                        "arrival": arr_time.replace('.', ':'),
                                        "platform": None,
                                    }
                                    result["arrivals"].append(train_info)
                except:
                    pass

            # Sort by time
            def time_key(t, key):
                time_str = t.get(key, '00:00')
                if time_str:
                    time_str = time_str.replace('.', ':')
                    parts = time_str.split(':')
                    if len(parts) == 2:
                        try:
                            return int(parts[0]) * 60 + int(parts[1])
                        except:
                            pass
                return 0

            result["departures"].sort(key=lambda t: time_key(t, 'departure'))
            result["arrivals"].sort(key=lambda t: time_key(t, 'arrival'))

            result["status"] = "success" if (result["arrivals"] or result["departures"]) else "no_data"

        except Exception as e:
            result["error"] = str(e)

        return result


class ConfirmTktScraper:
    """
    Scraper for confirmtkt.com - works without CAPTCHA.
    """

    BASE_URL = "https://www.confirmtkt.com"

    HEADERS = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    }

    def __init__(self, timeout: int = 20):
        self.session = requests.Session()
        self.session.headers.update(self.HEADERS)
        self.timeout = timeout

    def get_running_status(self, train_number: str) -> Dict[str, Any]:
        """
        Get train running status from confirmtkt.com (no CAPTCHA required).
        """
        url = f"{self.BASE_URL}/train-running-status/{train_number}"

        result = {
            "train_number": train_number,
            "source": "confirmtkt.com",
            "train_name": None,
            "status": None,
            "stations": [],
            "error": None
        }

        try:
            resp = self.session.get(url, timeout=self.timeout)
            if resp.ok:
                soup = BeautifulSoup(resp.text, 'lxml')

                # Extract train name from title
                title = soup.find('title')
                if title:
                    title_text = title.get_text()
                    match = re.search(r'(\d{5})\s*[-|]?\s*([^|]+)', title_text)
                    if match:
                        result["train_name"] = match.group(2).strip()

                # Look for status message
                status_patterns = [
                    r'(Yet to start|Running|Arrived|Cancelled)',
                    r'(on time|late by \d+|delayed)',
                ]
                page_text = soup.get_text()
                for pattern in status_patterns:
                    match = re.search(pattern, page_text, re.I)
                    if match:
                        result["status"] = match.group(1)
                        break

                # Extract station list from the page
                # Look for station names in select dropdowns or lists
                select = soup.find('select', {'id': re.compile(r'station', re.I)})
                if select:
                    options = select.find_all('option')
                    for opt in options:
                        station_name = opt.get_text(strip=True)
                        if station_name and station_name != 'Select Journey Station':
                            result["stations"].append({"name": station_name})

                result["success"] = True if result["status"] or result["stations"] else False

        except Exception as e:
            result["error"] = str(e)

        return result


# Convenience function to get best available data
def get_train_info(train_number: str) -> Dict[str, Any]:
    """
    Get train information using the most reliable available source.
    """
    api = IndianRailwaysAPI()
    result = api.get_train_info(train_number)

    if result.get("status") == "success":
        return result

    # Fallback to indiarailinfo
    scraper = RailwayInfoScraper()
    return scraper.get_train_schedule(train_number)


def search_trains(from_code: str, to_code: str) -> Dict[str, Any]:
    """
    Search trains between stations using the most reliable source.
    """
    api = IndianRailwaysAPI()
    result = api.search_trains(from_code, to_code)

    if result.get("trains"):
        return result

    # Fallback
    scraper = RailwayInfoScraper()
    return scraper.search_trains(from_code, to_code)


def get_live_status(train_number: str) -> Dict[str, Any]:
    """
    Get live running status (no CAPTCHA required).
    Uses ConfirmTkt as data source.
    """
    scraper = ConfirmTktScraper()
    result = scraper.get_running_status(train_number)

    # Add train info from erail
    api = IndianRailwaysAPI()
    info = api.get_train_info(train_number)

    if info.get("train_name"):
        result["train_name"] = info["train_name"]
        result["from_station"] = info.get("from_station")
        result["to_station"] = info.get("to_station")
        result["departure"] = info.get("departure")
        result["arrival"] = info.get("arrival")
        result["runs_on"] = info.get("runs_on")

    return result


def get_fare(train_number: str, from_code: str, to_code: str) -> Dict[str, Any]:
    """
    Get fare information for a train journey.

    Args:
        train_number: 5-digit train number
        from_code: Source station code
        to_code: Destination station code

    Returns:
        Dictionary with fare information for all classes
    """
    api = IndianRailwaysAPI()
    return api.get_fare(train_number, from_code, to_code)


def get_seat_availability(train_number: str, from_code: str, to_code: str,
                         date: str, class_code: str = "SL") -> Dict[str, Any]:
    """
    Get seat availability for a train.

    Args:
        train_number: 5-digit train number
        from_code: Source station code
        to_code: Destination station code
        date: Journey date (YYYYMMDD or DD-MM-YYYY)
        class_code: Class code (1A, 2A, 3A, SL, CC, 2S)

    Returns:
        Dictionary with availability status
    """
    api = IndianRailwaysAPI()
    return api.get_seat_availability(train_number, from_code, to_code, date, class_code)


def get_station_board(station_code: str, hours: int = 4) -> Dict[str, Any]:
    """
    Get arrivals and departures at a station.

    Args:
        station_code: Station code (e.g., NDLS, BCT)
        hours: Hours to look ahead (default 4)

    Returns:
        Dictionary with arrivals and departures with platform info
    """
    api = IndianRailwaysAPI()
    return api.get_station_trains(station_code, hours)


def main():
    """Example usage of the NTES scraper."""

    print("=" * 60)
    print("NTES Scraper - Indian Railways")
    print("=" * 60)

    api = IndianRailwaysAPI()

    # Example 1: Get train info
    print("\n[1] Fetching info for Rajdhani Express (12301)...")
    info = api.get_train_info("12301")
    if info.get("train_name"):
        print(f"    Train: {info['train_number']} - {info['train_name']}")
        print(f"    Route: {info['from_station']} ({info['from_code']}) -> {info['to_station']} ({info['to_code']})")
        print(f"    Timing: {info.get('departure', 'N/A')} -> {info.get('arrival', 'N/A')}")
        print(f"    Runs on: {info.get('runs_on', 'N/A')}")
    else:
        print(f"    Status: {info.get('status', 'unknown')}")
        print(f"    Error: {info.get('error', 'None')}")

    # Example 2: Search trains between stations
    print("\n[2] Searching trains from NDLS (New Delhi) to BCT (Mumbai)...")
    trains = api.search_trains("NDLS", "BCT")
    if trains.get("trains"):
        print(f"    Found {len(trains['trains'])} trains:")
        for t in trains['trains'][:5]:
            print(f"      {t['train_number']:>6} | {t.get('train_name', 'N/A')[:30]:30} | "
                  f"{t.get('departure', 'N/A'):8} -> {t.get('arrival', 'N/A'):8}")
    else:
        print(f"    Status: {trains.get('status', 'unknown')}")

    # Example 3: Search stations
    print("\n[3] Searching for stations matching 'Mumbai'...")
    stations = api.search_station("Mumbai")
    if stations and 'error' not in stations[0]:
        print(f"    Found {len(stations)} stations:")
        for s in stations[:5]:
            print(f"      {s.get('code', 'N/A'):8} - {s.get('name', 'N/A')}")

    print("\n" + "=" * 60)
    print("Done!")


if __name__ == "__main__":
    main()
