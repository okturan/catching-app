## ADDED Requirements

### Requirement: One visual world on every page
Every page SHALL use the wall palette (`$wall #F2EFE9`, `$face #FFFFFF`, `$ink #141414`, `$enamel #24405E`, `$signal #D7262A`, `$awake #FFC65A`), self-hosted Schibsted Grotesk for words and Martian Mono for every time or slot label, enamel `.plate` elements for labels and primary actions, and white `.face` panels for content. Pages MUST NOT load fonts, images, video or stylesheets from a third-party host; the CSP SHALL restrict `font-src`, `img-src` and `media-src` to `self` (plus `data:` where needed).

#### Scenario: No external assets
- **WHEN** any page is rendered
- **THEN** no `res.cloudinary.com` or `fonts.googleapis.com` URL appears in the HTML or CSS

### Requirement: The landing page first viewport
`pages#home` SHALL render, above the fold at 1440 px, a row of five live clocks (`#clock-wall`) with the visitor's zone first, each over an enamel plate showing city, local time and UTC offset; a range input `#shared-moment` (−12 h to +12 h in 15-minute steps) that moves every clock together and whose track paints the hours when all five cities are between 08:00 and 23:00 local in yellow; the tagline "We have some catching app to do!" as the `h1`; one sentence; a "Plan a meeting" link to `events#new`; and a quiet "Lost your organizer link?" link to `organizer_links#new`. Hands SHALL sweep from noon to now on load unless `prefers-reduced-motion` is set. Below 900 px the row SHALL show three clocks.

#### Scenario: Ruler moves the clocks
- **WHEN** the visitor drags the ruler to +3 h
- **THEN** every plate shows its city's local time three hours from now and the output reads "+3h"

### Requirement: App pages in the same world
The navbar SHALL show a `Catching.app` brand plate, sentence-case links, and a "Plan a meeting" plate; the footer SHALL carry a plate with the year and links to plan, lost-link recovery and SECURITY.md. The grid's day headers SHALL be enamel plates, its row labels Martian Mono, offered cells white with a hairline, painted cells enamel with white text, consensus cells yellow-washed, and painted consensus cells full yellow. The dashboard SHALL list participations as `.event-face` panels under "Organizing" and "Invited" headings with counts and no static promotional content.

#### Scenario: Dashboard lists only participations
- **WHEN** a signed-in user opens the dashboard
- **THEN** each participation is one `.event-face` link and no tabs or sample activities render
