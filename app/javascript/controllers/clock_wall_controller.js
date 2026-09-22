import { Controller } from "@hotwired/stimulus";
import { DateTime } from "luxon";

import { buildCard, offsetLabel, paintHands, pickCities, shiftLabel } from "../lib/clock";

const AWAKE_FROM = 8;
const AWAKE_TO = 23;

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
