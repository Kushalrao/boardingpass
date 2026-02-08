"""
Train Scraper API - FastAPI service for Indian Railways data
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime
import os

from scrapers.pnr_status import PNRStatusChecker
from scrapers.confirmtkt_scraper import ConfirmTktScraper
from scrapers.ntes_scraper import IndianRailwaysAPI

app = FastAPI(
    title="Train Scraper API",
    description="API for fetching Indian Railways train data",
    version="1.0.0"
)

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
            stations.append(ScheduleStation(
                code=s.get("code", ""),
                name=s.get("name", ""),
                arrival=s.get("arrival"),
                departure=s.get("departure"),
                halt=s.get("halt"),
                distance=s.get("distance"),
                dayNumber=s.get("day")
            ))

        return TrainScheduleResponse(
            success=result.get("success", False),
            trainNumber=train_number,
            trainName=result.get("train_name"),
            runningDays=result.get("running_days", []),
            stations=stations,
            error=result.get("error")
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
    Get live running status of a train

    Args:
        train_number: 5-digit train number
        date: Optional date in YYYYMMDD format
    """
    if not train_number.isdigit() or len(train_number) != 5:
        raise HTTPException(status_code=400, detail="Invalid train number. Must be 5 digits.")

    try:
        scraper = ConfirmTktScraper(headless=True)
        result = scraper.get_live_status(train_number, date)

        stations = []
        for s in result.get("stations", []):
            stations.append(LiveStationStatus(
                code=s.get("code", ""),
                name=s.get("name", ""),
                scheduledArrival=s.get("scheduled_arrival"),
                actualArrival=s.get("actual_arrival"),
                delay=s.get("delay"),
                status=s.get("status", "upcoming")
            ))

        return LiveStatusResponse(
            success=result.get("success", False),
            trainNumber=train_number,
            trainName=result.get("train_name"),
            currentStation=result.get("current_station"),
            lastUpdated=result.get("last_updated"),
            delay=result.get("delay"),
            stations=stations,
            error=result.get("error")
        )

    except Exception as e:
        return LiveStatusResponse(
            success=False,
            trainNumber=train_number,
            error=str(e)
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
