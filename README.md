# RescueLink – Disaster Response & SOS Network

RescueLink is a disaster‑management mobile application designed to provide **real‑time disaster alerts**, **offline emergency communication**, and **rescue coordination** during natural disasters.

The app transforms smartphones into a **community‑driven emergency network**, allowing users to receive warnings, send SOS signals, and help rescuers locate victims even when internet connectivity is unavailable.

---

## 🌍 Features

### 📡 Real‑Time Disaster Alerts
RescueLink retrieves disaster information from global disaster monitoring services and public data sources.

The backend analyzes this data and sends alerts to users who are within a potentially affected area, helping them prepare or move to safer locations.

### 🆘 SOS Emergency System
If a user becomes trapped during a disaster:

- The app retrieves the user’s location using the device GPS.
- The SOS message containing coordinates is broadcast using **Bluetooth**.
- Nearby phones running RescueLink receive and relay the signal, creating a **device‑to‑device mesh network**.

This allows SOS messages to travel across multiple devices even without internet connectivity.

### 📍 Offline Rescue Navigation
Rescuers who receive an SOS signal can navigate to the victim’s location using:

- GPS coordinates
- distance calculations
- directional guidance

This helps rescuers reach victims even when network infrastructure is unavailable.

### 📖 Safety Guide
The application includes an offline safety guide with instructions for different disasters such as:

- Earthquakes
- Floods
- Storms
- Fires

Users can quickly access emergency precautions during critical situations.

---

## 🏗 System Architecture
The system consists of three main components:

1. **Disaster Data Sources**
2. **Backend Server**
3. **Mobile Application**

High‑level flow:

```
Disaster Data Sources
        ↓
Backend Server
        ↓
Database
        ↓
Alert Processing
        ↓
Mobile Application
```

### Mobile Application
Handles:

- User interface
- GPS location tracking
- SOS broadcasting
- Receiving alerts
- Safety guidance

### Backend Server
Responsible for:

- Collecting disaster data
- Processing disaster events
- Sending alerts to affected users

### Mesh Communication Network
A Bluetooth‑based relay system that allows devices to forward SOS messages to extend communication range.

---

## 🔁 SOS Mesh Network Example

```
Victim Phone
      ↓
Nearby Phone
      ↓
Another Phone
      ↓
Rescuer Device
```

Each device acts as a relay node, forwarding SOS signals through nearby devices.

---

## 🧭 System Flow Diagrams

### 🚨 Disaster Alert System Flow
![Disaster Alert System Flow](image3)

### 🆘 SOS Emergency Flow
![SOS Emergency Flow](image2)

### 📶 Bluetooth Mesh Message Propagation Flow
![Bluetooth Mesh Message Propagation Flow](image1)

---

## 🛠 Technologies Used

- Flutter
- Dart
- Bluetooth Low Energy (BLE)
- GPS Location Services
- Backend Server
- Database

---

## 🚀 Future Improvements

- Offline maps for rescue navigation
- Improved mesh networking range
- Disaster prediction models
- Integration with official emergency services
- End‑to‑end encrypted SOS messages

---

## ⚠ Disclaimer
RescueLink is an experimental disaster-response tool intended to assist in emergency communication and awareness. It should not replace official emergency services.