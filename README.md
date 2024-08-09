# Catching App

Catching App is a web application designed to facilitate event planning and scheduling among friends. Users can create events, invite friends, and define available time slots for meetings, making it easier to coordinate schedules.

## Features

- User authentication with Devise
- Create and manage events
- Invite friends to events
- Define and visualize available time slots
- Responsive design with Bootstrap
- User-friendly interface

## Technologies Used

- Ruby on Rails
- PostgreSQL
- ActionCable for real-time features
- Bootstrap for styling
- JavaScript and jQuery for interactivity
- Moment.js for date and time manipulation

## Setup Instructions

To set up the application locally, follow these steps:

1. **Clone the repository:**

```bash
git clone https://github.com/yourusername/catching-app.git
cd catching-app
```

2. **Install dependencies:***

Ensure you have Ruby and Rails installed. Then run:

```bash
bundle install
yarn install
```

3. **Set up the database:**

Create and migrate the database:

```bash
rails db:create
rails db:migrate
```

4. **Run the application:**

Start the Rails server:

```bash
rails server
```
You can now access the application at http://localhost:3000.

## Usage

Sign up for a new account or log in with an existing account.
Navigate to the dashboard to create new events or view your existing events.
Invite friends to your events and define available time slots for meetings.
