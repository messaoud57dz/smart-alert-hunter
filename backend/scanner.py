
import json
import urllib.request
import urllib.error

BASE_URL = "https://api.binance.com"
MAX_PRICE = 1.0
MIN_VOLUME = 1_000_000
MAX_COINS = 30


def api_get(path, params=""):
    url = BASE_URL + path
    if params:
        url += "?" + params

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "SmartAlertHunter/1.0"}
    )

    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode())


def ema(values, period):
    if len(values) < period:
        return None

    alpha = 2 / (period + 1)
    result = sum(values[:period]) / period

    for value in values[period:]:
        result = value * alpha + result * (1 - alpha)

    return result


def find_bullish_ob(candles):
    # البحث عن شمعة هابطة قبل حركة صعود قوية
    start = max(2, len(candles) - 35)

    for i in range(len(candles) - 4, start - 1, -1):
        candle = candles[i]

        open_price = float(candle[1])
        close_price = float(candle[4])

        if close_price >= open_price:
            continue

        previous_high = max(float(c[2]) for c in candles[max(0, i-5):i])

        for j in range(i + 1, min(i + 4, len(candles))):
            next_close = float(candles[j][4])

            if next_close > previous_high:
                return {
                    "low": min(open_price, close_price),
                    "high": max(open_price, close_price)
                }

    return None


def scan():
    print("Starting Smart Alert Hunter V1...")

    exchange = api_get("/api/v3/exchangeInfo")
    tickers = api_get("/api/v3/ticker/24hr")

    spot_symbols = {
        item["symbol"]
        for item in exchange["symbols"]
        if item["status"] == "TRADING"
        and item["quoteAsset"] == "USDT"
        and item["isSpotTradingAllowed"]
    }

    candidates = []

    for ticker in tickers:
        symbol = ticker["symbol"]

        if symbol not in spot_symbols:
            continue

        price = float(ticker["lastPrice"])
        volume = float(ticker["quoteVolume"])

        if 0 < price <= MAX_PRICE and volume >= MIN_VOLUME:
            candidates.append({
                "symbol": symbol,
                "price": price,
                "volume": volume
            })

    candidates.sort(key=lambda x: x["volume"], reverse=True)
    results = []

    for coin in candidates[:MAX_COINS]:
        symbol = coin["symbol"]

        try:
            candles = api_get(
                "/api/v3/klines",
                f"symbol={symbol}&interval=1d&limit=100"
            )

            closes = [float(c[4]) for c in candles[:-1]]

            if len(closes) < 50:
                continue

            ema20 = ema(closes, 20)
            ema50 = ema(closes, 50)
            price = coin["price"]

            if not (ema20 > ema50 and price > ema20):
                continue

            ob = find_bullish_ob(candles[:-1])

            if not ob:
                continue

            distance = ((price - ob["high"]) / ob["high"]) * 100

            if distance < 0:
                status = "INSIDE_DEMAND_ZONE"
            elif distance <= 5:
                status = "NEAR_DEMAND_ZONE"
            else:
                status = "WAIT"

            results.append({
                "symbol": symbol,
                "price": price,
                "volume_24h": round(coin["volume"], 2),
                "ema20": round(ema20, 8),
                "ema50": round(ema50, 8),
                "demand_zone": {
                    "low": round(ob["low"], 8),
                    "high": round(ob["high"], 8)
                },
                "distance_percent": round(distance, 2),
                "status": status
            })

        except Exception as error:
            print(f"Skipped {symbol}: {error}")

    output = {
        "project": "Smart Alert Hunter V1",
        "results_count": len(results),
        "results": results
    }

    print(json.dumps(output, indent=2))
    return output


if __name__ == "__main__":
    try:
        scan()
    except Exception as error:
        print("Scanner error:", error)
