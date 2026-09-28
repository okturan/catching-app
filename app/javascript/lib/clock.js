// The pieces of the landing page's clock wall: a card per city, its SVG
// clock and the labels under it.

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

export { buildCard, offsetLabel, paintHands, pickCities, shiftLabel };
