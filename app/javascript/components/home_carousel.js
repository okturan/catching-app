import Carousel from "bootstrap/js/dist/carousel";

const initHomeCarousel = () => {
  const element = document.querySelector("#carouselExampleIndicators");
  if (!element) return;

  Carousel.getOrCreateInstance(element, {
    interval: 7000,
    pause: false,
  });

  element.addEventListener("slid.bs.carousel", () => {
    const video = element.querySelector(".carousel-item.active video");
    if (!video) return;

    video.pause();
    video.currentTime = 0;
    video.play().catch(() => {
      // Browsers may deny autoplay until the user interacts with the page.
    });
  });
};

export { initHomeCarousel };
