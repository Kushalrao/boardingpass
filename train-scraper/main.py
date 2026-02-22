"""
Train Scraper API - FastAPI service for Indian Railways data
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime
import os
import re

import logging

from scrapers.pnr_status import PNRStatusChecker
from scrapers.confirmtkt_scraper import ConfirmTktScraper
from scrapers.ntes_scraper import IndianRailwaysAPI, RailwayInfoScraper
from scrapers.ixigo_scraper import IxigoScraper

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Train Scraper API",
    description="API for fetching Indian Railways train data",
    version="1.0.0"
)

# Helper functions
def parse_delay(delay_value) -> Optional[int]:
    """Convert delay string/value to integer minutes."""
    if delay_value is None:
        return None
    if isinstance(delay_value, int):
        return delay_value
    if isinstance(delay_value, str):
        s = delay_value.strip().lower()
        if s in ('right time', 'on time', 'rt', '--', ''):
            return 0
        match = re.search(r'(\d+)', s)
        if match:
            minutes = int(match.group(1))
            if 'hr' in s or 'hour' in s:
                minutes *= 60
            return minutes
    return None


def clean_train_name(name: Optional[str]) -> Optional[str]:
    """Remove garbage text from train name."""
    if not name:
        return name
    name = name.split('\n')[0].strip()
    # Remove trailing noise like "CHANGE", "G", "N" etc.
    name = re.sub(r'\s*(CHANGE|Running Status|Live Status).*$', '', name, flags=re.I).strip()
    return name if name else None


def normalize_station_name(name: str) -> str:
    """Normalize station name for matching across sources."""
    if not name:
        return ""
    s = name.strip().lower()
    s = re.sub(r'\b(jn|junction|junc|terminus|term|central|city|halt|road|t)\b', '', s)
    s = re.sub(r'[^a-z0-9\s]', '', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def merge_live_status(primary: Dict[str, Any], enrichment: Dict[str, Any]) -> Dict[str, Any]:
    """
    Merge enrichment data (ixigo) into primary data (ConfirmTkt).
    Fills in missing platform, halt, actual_arrival, code fields.
    If primary has no stations, uses enrichment entirely.
    """
    if not primary.get("stations"):
        return enrichment
    if not enrichment.get("stations"):
        return primary

    # Build lookup from enrichment stations by code and normalized name
    enrich_by_code = {}
    enrich_by_name = {}
    for s in enrichment["stations"]:
        code = s.get("code", "")
        name = s.get("station") or s.get("name", "")
        if code:
            enrich_by_code[code.upper()] = s
        norm = normalize_station_name(name)
        if norm:
            enrich_by_name[norm] = s

    # Merge into primary stations
    for station in primary["stations"]:
        p_code = station.get("code", "")
        p_name = station.get("station") or station.get("name", "")
        norm = normalize_station_name(p_name)

        # Find match: prefer code, fallback to name
        match = None
        if p_code:
            match = enrich_by_code.get(p_code.upper())
        if not match and norm:
            match = enrich_by_name.get(norm)

        if match:
            if not station.get("platform") and match.get("platform"):
                station["platform"] = match["platform"]
            if not station.get("halt") and match.get("halt"):
                station["halt"] = match["halt"]
            if not station.get("scheduled_arrival") and not station.get("arrival"):
                station["scheduled_arrival"] = match.get("scheduled_arrival")
            if not station.get("actual_arrival") and match.get("actual_arrival"):
                station["actual_arrival"] = match["actual_arrival"]
            if station.get("delay") is None and match.get("delay") is not None:
                station["delay"] = match["delay"]
            if not station.get("code") and match.get("code"):
                station["code"] = match["code"]

    # Merge top-level fields if missing in primary
    if not primary.get("train_name") and enrichment.get("train_name"):
        primary["train_name"] = enrichment["train_name"]
    if not primary.get("current_location") and enrichment.get("current_location"):
        primary["current_location"] = enrichment["current_location"]
    if not primary.get("last_updated") and enrichment.get("last_updated"):
        primary["last_updated"] = enrichment["last_updated"]

    return primary


# Response Models
class Station(BaseModel):
    code: str
    name: str
    time: Optional[str] = None

class Passenger(BaseModel):
    number: int
    bookingStatus: str
    currentStatus: str
    coach: Optional[str] = None
    berth: Optional[str] = None

class PnrStatusResponse(BaseModel):
    success: bool
    pnr: str
    trainNumber: Optional[str] = None
    trainName: Optional[str] = None
    journeyDate: Optional[str] = None
    fromStation: Optional[Station] = None
    toStation: Optional[Station] = None
    travelClass: Optional[str] = None
    quota: Optional[str] = None
    passengers: List[Passenger] = []
    chartStatus: Optional[str] = None
    overallStatus: Optional[str] = None
    confirmationChance: Optional[str] = None
    error: Optional[str] = None

class ScheduleStation(BaseModel):
    code: str
    name: str
    arrival: Optional[str] = None
    departure: Optional[str] = None
    halt: Optional[str] = None
    distance: Optional[int] = None
    dayNumber: Optional[int] = None

class TrainScheduleResponse(BaseModel):
    success: bool
    trainNumber: str
    trainName: Optional[str] = None
    runningDays: List[str] = []
    stations: List[ScheduleStation] = []
    error: Optional[str] = None

class LiveStationStatus(BaseModel):
    code: str
    name: str
    scheduledArrival: Optional[str] = None
    actualArrival: Optional[str] = None
    delay: Optional[int] = None
    halt: Optional[str] = None
    platform: Optional[int] = None
    status: str  # 'departed', 'arrived', 'upcoming'

class LiveStatusResponse(BaseModel):
    success: bool
    trainNumber: str
    trainName: Optional[str] = None
    currentStation: Optional[str] = None
    lastUpdated: Optional[str] = None
    delay: Optional[int] = None
    stations: List[LiveStationStatus] = []
    error: Optional[str] = None

class SearchTrain(BaseModel):
    trainNumber: str
    trainName: str
    departure: str
    arrival: str
    duration: Optional[str] = None
    runningDays: List[str] = []

class SearchTrainsResponse(BaseModel):
    success: bool
    trains: List[SearchTrain] = []
    error: Optional[str] = None


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@app.get("/pnr/{pnr_number}", response_model=PnrStatusResponse)
async def get_pnr_status(pnr_number: str):
    """
    Get PNR status for a 10-digit PNR number
    """
    # Validate PNR
    if not pnr_number.isdigit() or len(pnr_number) != 10:
        raise HTTPException(status_code=400, detail="Invalid PNR. Must be 10 digits.")

    try:
        checker = PNRStatusChecker(headless=True)
        result = checker.check_pnr(pnr_number)

        # Transform to response model
        passengers = []
        for p in result.get("passengers", []):
            passengers.append(Passenger(
                number=p.get("passenger", 0),
                bookingStatus=p.get("booking_status", ""),
                currentStatus=p.get("current_status", ""),
                coach=p.get("coach"),
                berth=str(p.get("berth")) if p.get("berth") else None
            ))

        from_station = None
        if result.get("from_station"):
            # Parse "Station Name (CODE)" format
            fs = result["from_station"]
            if "(" in fs:
                name = fs.split("(")[0].strip()
                code = fs.split("(")[1].replace(")", "").strip()
            else:
                name = fs
                code = fs
            from_station = Station(
                code=code,
                name=name,
                time=result.get("departure_time")
            )

        to_station = None
        if result.get("to_station"):
            ts = result["to_station"]
            if "(" in ts:
                name = ts.split("(")[0].strip()
                code = ts.split("(")[1].replace(")", "").strip()
            else:
                name = ts
                code = ts
            to_station = Station(
                code=code,
                name=name,
                time=result.get("arrival_time")
            )

        return PnrStatusResponse(
            success=result.get("success", False),
            pnr=pnr_number,
            trainNumber=result.get("train_number"),
            trainName=result.get("train_name"),
            journeyDate=result.get("journey_date"),
            fromStation=from_station,
            toStation=to_station,
            travelClass=result.get("class"),
            quota=result.get("quota"),
            passengers=passengers,
            chartStatus=result.get("chart_status"),
            overallStatus=result.get("overall_status"),
            confirmationChance=result.get("confirmation_chance"),
            error=result.get("error")
        )

    except Exception as e:
        return PnrStatusResponse(
            success=False,
            pnr=pnr_number,
            error=str(e)
        )


@app.get("/schedule/{train_number}", response_model=TrainScheduleResponse)
async def get_train_schedule(train_number: str):
    """
    Get train schedule with all stops
    """
    if not train_number.isdigit() or len(train_number) != 5:
        raise HTTPException(status_code=400, detail="Invalid train number. Must be 5 digits.")

    try:
        scraper = ConfirmTktScraper(headless=True)
        result = scraper.get_train_schedule(train_number)

        stations = []
        for s in result.get("stations", []):
            # Handle both confirmtkt key formats
            code = s.get("code", s.get("station_code", ""))
            name = s.get("name", s.get("station_name", ""))
            distance = s.get("distance", s.get("distance_km"))
            if distance is not None:
                try:
                    distance = int(float(distance))
                except (ValueError, TypeError):
                    distance = None
            day = s.get("day", s.get("dayNumber"))
            if day is not None:
                try:
                    day = int(day)
                except (ValueError, TypeError):
                    day = None

            stations.append(ScheduleStation(
                code=code,
                name=name,
                arrival=s.get("arrival"),
                departure=s.get("departure"),
                halt=s.get("halt", s.get("halt_time")),
                distance=distance,
                dayNumber=day
            ))

        train_name = clean_train_name(result.get("train_name"))

        # Fallback: if confirmtkt returned no stations, try RailwayInfoScraper
        if not stations:
            try:
                ri_scraper = RailwayInfoScraper()
                ri_result = ri_scraper.get_train_schedule(train_number)
                for s in ri_result.get("stations", []):
                    distance = s.get("distance")
                    if distance is not None:
                        try:
                            distance = int(re.sub(r'[^\d]', '', str(distance))) if distance else None
                        except (ValueError, TypeError):
                            distance = None
                    day = s.get("day")
                    if day is not None:
                        try:
                            day = int(day)
                        except (ValueError, TypeError):
                            day = None
                    stations.append(ScheduleStation(
                        code=s.get("station_code", ""),
                        name=s.get("station_name", ""),
                        arrival=s.get("arrival"),
                        departure=s.get("departure"),
                        halt=s.get("halt"),
                        distance=distance,
                        dayNumber=day
                    ))
                if not train_name:
                    train_name = clean_train_name(ri_result.get("train_name"))
            except Exception:
                pass

        # Fallback: get train name from erail if still missing
        if not train_name:
            try:
                api = IndianRailwaysAPI()
                info = api.get_train_info(train_number)
                train_name = info.get("train_name")
            except Exception:
                pass

        return TrainScheduleResponse(
            success=len(stations) > 0,
            trainNumber=train_number,
            trainName=train_name,
            runningDays=result.get("running_days", []),
            stations=stations,
            error=result.get("error") if not stations else None
        )

    except Exception as e:
        return TrainScheduleResponse(
            success=False,
            trainNumber=train_number,
            error=str(e)
        )


@app.get("/live/{train_number}", response_model=LiveStatusResponse)
async def get_live_status(train_number: str, date: Optional[str] = None):
    """
    Get live running status of a train.
    Uses ConfirmTkt as primary source, enriched with ixigo data (platform numbers, halt times).
    Falls back to ixigo-only if ConfirmTkt fails.

    Args:
        train_number: 5-digit train number
        date: Optional date in YYYYMMDD format
    """
    if not train_number.isdigit() or len(train_number) != 5:
        raise HTTPException(status_code=400, detail="Invalid train number. Must be 5 digits.")

    confirmtkt_result = None
    ixigo_result = None

    # Step 1: Try ConfirmTkt (primary source)
    try:
        scraper = ConfirmTktScraper(headless=True)
        confirmtkt_result = scraper.get_live_status(train_number, date)
    except Exception as e:
        logger.error(f"ConfirmTkt scraper failed for {train_number}: {e}")
        confirmtkt_result = {
            "success": False, "stations": [],
            "error": str(e), "train_number": train_number,
        }

    # Step 2: Try ixigo via Firecrawl (enrichment source)
    try:
        ixigo_scraper = IxigoScraper()
        ixigo_result = ixigo_scraper.get_live_status(train_number, date)
    except Exception as e:
        # Silently fail - ixigo is optional enrichment
        logger.debug(f"ixigo scraper unavailable for {train_number}: {e}")
        ixigo_result = None

    # Step 3: Merge results
    if confirmtkt_result and confirmtkt_result.get("success") and confirmtkt_result.get("stations"):
        if ixigo_result and ixigo_result.get("stations"):
            result = merge_live_status(confirmtkt_result, ixigo_result)
        else:
            result = confirmtkt_result
    elif ixigo_result and ixigo_result.get("success") and ixigo_result.get("stations"):
        result = ixigo_result
    else:
        result = confirmtkt_result or {
            "success": False, "stations": [],
            "error": "All scrapers failed", "train_number": train_number,
        }

    # Step 4: Transform to response model
    stations = []
    for s in result.get("stations", []):
        stations.append(LiveStationStatus(
            code=s.get("code", s.get("station_code", "")),
            name=s.get("name", s.get("station", "")),
            scheduledArrival=s.get("scheduled_arrival", s.get("arrival")),
            actualArrival=s.get("actual_arrival"),
            delay=parse_delay(s.get("delay")),
            halt=s.get("halt"),
            platform=s.get("platform"),
            status=s.get("status", "upcoming")
        ))

    return LiveStatusResponse(
        success=result.get("success", False),
        trainNumber=train_number,
        trainName=clean_train_name(result.get("train_name")),
        currentStation=result.get("current_station", result.get("current_location")),
        lastUpdated=result.get("last_updated"),
        delay=parse_delay(result.get("delay")),
        stations=stations,
        error=result.get("error")
    )


@app.get("/search", response_model=SearchTrainsResponse)
async def search_trains(
    from_station: str,
    to_station: str,
    date: Optional[str] = None
):
    """
    Search trains between two stations

    Args:
        from_station: Source station code (e.g., NDLS)
        to_station: Destination station code (e.g., BCT)
        date: Optional date in YYYYMMDD format
    """
    from_station = from_station.upper()
    to_station = to_station.upper()

    try:
        api = IndianRailwaysAPI()
        result = api.search_trains(from_station, to_station)

        trains = []
        for t in result.get("trains", []):
            trains.append(SearchTrain(
                trainNumber=t.get("train_number", ""),
                trainName=t.get("train_name", ""),
                departure=t.get("departure", ""),
                arrival=t.get("arrival", ""),
                duration=t.get("duration"),
                runningDays=t.get("running_days", [])
            ))

        return SearchTrainsResponse(
            success=True,
            trains=trains
        )

    except Exception as e:
        return SearchTrainsResponse(
            success=False,
            error=str(e)
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
