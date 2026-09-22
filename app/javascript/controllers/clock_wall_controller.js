import { Controller } from "@hotwired/stimulus";
import { DateTime } from "luxon";

const CITIES = [
  ["Europe/Istanbul", "Istanbul"],
  ["Europe/Berlin", "Berlin"],
  ["America/New_York", "New York"],
  ["Asia/Tokyo", "Tokyo"],
  ["America/Sao_Paulo", "São Paulo"],
  ["Asia/Kolkata", "Mumbai"],
  ["Australia/Sydney", "Sydney"],
];
const SVG = "http://www.w3.org/2000/svg";
const AWAKE_FROM = 8;
const AWAKE_TO = 23;

const svgElement = (name, attributes) => {
  const node = document.createElementNS(SVG, name);
  Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, value));
  return node;
};

const buildClock = () => {
  const svg = svgElement("svg", { class: "clock", viewBox: "0 0 100 100", role: "img", "aria-hidden": "true" });
  svg.appendChild(svgElement("circle", { class: "clock-face", cx: 50, cy: 50, r: 48 }));
  svg.appendChild(svgElement("circle", { class: "clock-ring", cx: 50, cy: 50, r: 44 }));
  for (let index = 0; index < 60; index += 1) {
    const major = index % 5 === 0;
    const angle = (index / 60) * Math.PI * 2;
    const outer = 46;
    const inner = major ? 40 : 43;
    svg.appendChild(svgElement("line", {
      class: `clock-tick${major ? " clock-tick-major" : ""}`,
      x1: 50 + Math.sin(angle) * inner, y1: 50 - Math.cos(angle) * inner,
      x2: 50 + Math.sin(angle) * outer, y2: 50 - Math.cos(angle) * outer,
    }));
  }
  const hands = {
    hour: svgElement("line", { class: "clock-hand clock-hour", x1: 50, y1: 50, x2: 50, y2: 26 }),
    minute: svgElement("line", { class: "clock-hand clock-minute", x1: 50, y1: 50, x2: 50, y2: 16 }),
    second: svgElement("line", { class: "clock-hand clock-second", x1: 50, y1: 58, x2: 50, y2: 12 }),
  };
  Object.values(hands).forEach((hand) => svg.appendChild(hand));
  svg.appendChild(svgElement("circle", { class: "clock-pin", cx: 50, cy: 50, r: 2.2 }));
  return { svg, hands };
};

const zoneLabel = (zone) => zone.split("/").pop().replace(/_/g, " ");

const offsetLabel = (local) => {
  const minutes = local.offset;
  const sign = minutes >= 0 ? "+" : "−";
  const hours = Math.floor(Math.abs(minutes) / 60);
  const rest = Math.abs(minutes) % 60;
  return `UTC${sign}${hours}${rest ? `:${String(rest).padStart(2, "0")}` : ""}`;
};

const buildCard = (zone, city, visitor) => {
  const card = document.createElement("div");
  card.className = `clock-card${visitor ? " is-visitor" : ""}`;
  card.dataset.zone = zone;
  const { svg, hands } = buildClock();
  const plate = document.createElement("div");
  plate.className = "plate";
  const cityLabel = document.createElement("span");
  cityLabel.className = "plate-city";
  cityLabel.textContent = visitor ? `You · ${city}` : city;
  const time = document.createElement("span");
  time.className = "plate-time";
  const offset = document.createElement("span");
  offset.className = "plate-offset";
  plate.append(cityLabel, time, offset);
  card.append(svg, plate);
  return { card, hands, time, offset, zone, city };
};

const pickCities = (visitorZone) => {
  const visitor = [visitorZone, zoneLabel(visitorZone)];
  const others = CITIES.filter(([zone]) => zone !== visitorZone).slice(0, 4);
  return [visitor, ...others];
};

const paintHands = (entry, local) => {
  const seconds = local.second + local.millisecond / 1000;
  const minutes = local.minute + seconds / 60;
  const hours = (local.hour % 12) + minutes / 60;
  entry.hands.hour.style.transform = `rotate(${hours * 30}deg)`;
  entry.hands.minute.style.transform = `rotate(${minutes * 6}deg)`;
  entry.hands.second.style.transform = `rotate(${seconds * 6}deg)`;
};

// "now", "+3h", "−1h 30m": how far the ruler moved the shared moment.
const shiftLabel = (offsetMinutes) => {
  if (offsetMinutes === 0) return "now";
  const sign = offsetMinutes > 0 ? "+" : "−";
  const hours = Math.floor(Math.abs(offsetMinutes) / 60);
  const minutes = Math.abs(offsetMinutes) % 60;
  return `${sign}${hours}h${minutes ? ` ${minutes}m` : ""}`;
};

// The landing page's clock wall: five synchronized clocks, the visitor's zone
// first, driven by one shared instant that the ruler moves.
export default class extends Controller {
  static targets = ["clocks", "ruler", "awake", "label", "summary"];

  connect() {
    const visitorZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
    this.cards = pickCities(visitorZone).map(([zone, city], index) => buildCard(zone, city, index === 0));
    this.clocksTarget.replaceChildren(...this.cards.map((entry) => entry.card));
    this.offsetMinutes = 0;

    // One authored motion: hands start at noon and sweep to now.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.render();
    } else {
      this.cards.forEach((entry) => {
        Object.values(entry.hands).forEach((hand) => { hand.style.transform = "rotate(0deg)"; });
        entry.card.querySelector(".clock").setAttribute("data-sweep", "");
      });
      requestAnimationFrame(() => requestAnimationFrame(() => this.render()));
      this.sweepEnd = setTimeout(() => {
        this.cards.forEach((entry) => entry.card.querySelector(".clock").removeAttribute("data-sweep"));
      }, 1600);
    }
    this.paintAwake();

    // A newsroom clock sweeps: render every frame (five small SVGs).
    const tick = () => {
      this.render();
      this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  }

  disconnect() {
    cancelAnimationFrame(this.frame);
    clearTimeout(this.sweepEnd);
  }

  move() {
    this.offsetMinutes = Number(this.rulerTarget.value);
    this.render();
  }

  render() {
    const instant = DateTime.now().plus({ minutes: this.offsetMinutes });
    this.cards.forEach((entry) => {
      const local = instant.setZone(entry.zone);
      paintHands(entry, local);
      entry.time.textContent = local.toFormat("HH:mm");
      entry.offset.textContent = offsetLabel(local);
      entry.card.title = `${entry.city}: ${local.toFormat("cccc HH:mm")}`;
    });
    this.labelTarget.textContent = shiftLabel(this.offsetMinutes);
  }

  // The awake band: every quarter hour of the ruler where all five cities
  // sit between 08:00 and 23:00 local time.
  paintAwake() {
    const min = Number(this.rulerTarget.min);
    const max = Number(this.rulerTarget.max);
    const step = Number(this.rulerTarget.step) || 15;
    const now = DateTime.now();
    const stops = [];
    let awakeMinutes = 0;
    for (let offset = min; offset < max; offset += step) {
      const instant = now.plus({ minutes: offset });
      const everyone = this.cards.every((entry) => {
        const { hour } = instant.setZone(entry.zone);
        return hour >= AWAKE_FROM && hour < AWAKE_TO;
      });
      if (everyone) awakeMinutes += step;
      const from = ((offset - min) / (max - min)) * 100;
      const to = ((offset + step - min) / (max - min)) * 100;
      stops.push(`${everyone ? "var(--awake)" : "transparent"} ${from.toFixed(2)}% ${to.toFixed(2)}%`);
    }
    this.awakeTarget.style.backgroundImage = `linear-gradient(to right, ${stops.join(", ")})`;

    const hours = Math.round(awakeMinutes / 60);
    this.summaryTarget.textContent = hours === 0
      ? "No hour in the 24 around now finds all five awake. That is why you paint a range."
      : `Yellow: ${hours} hour${hours === 1 ? "" : "s"} in the 24 around now when all five are awake.`;
  }
}
