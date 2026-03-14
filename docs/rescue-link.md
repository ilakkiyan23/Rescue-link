
# Disaster App – Developer Feature Documentation


## 1. Location Permission and GPS Retrieval


Package used: `geolocator`


Purpose:


Obtain the user’s current GPS coordinates.


### Step 1 – Check if location services are enabled


```dart
bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
```


Explanation:


This checks whether the device’s location service (GPS) is turned on.


Possible outcomes:

- `true` → GPS service is active
- `false` → GPS is disabled

If disabled, the function returns `null` and the app cannot get location.


---


### Step 2 – Check permission status


```dart
LocationPermission permission = await Geolocator.checkPermission();
```


Explanation:


This determines the current permission state granted by the user.


Possible values:

- `denied`
- `deniedForever`
- `whileInUse`
- `always`

---


### Step 3 – Request permission if needed


```dart
if (permission == LocationPermission.denied) {
  permission = await Geolocator.requestPermission();
}
```


Explanation:


If permission has not been granted yet, the app asks the user to allow location access.


---


### Step 4 – Handle permanent denial


```dart
if (permission == LocationPermission.deniedForever) {
  return null;
}
```


Explanation:


If the user permanently blocks location access, the app cannot request it again and must return `null`.


---


### Step 5 – Retrieve GPS coordinates


```dart
Position position = await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.high,
);
```


Explanation:


This function accesses the device GPS chip to determine the current latitude and longitude.


Example output:


```plain text
Latitude: 13.0827
Longitude: 80.2707
```


Internet connection is **not required** because GPS uses satellite signals.


---


# 2. Sending SOS via SMS


Package used: `url_launcher`


Purpose:


Open the device SMS app with a pre-filled message containing location information.


---


### Step 1 – Retrieve location


```dart
final position = await LocationService.getCurrentPosition();
```


Explanation:


Calls the location service to obtain the user’s coordinates before sending the message.


---


### Step 2 – Load emergency contacts


```dart
final contacts = await ContactService.loadContacts();
```


Explanation:


Retrieves stored phone numbers from local storage.


Example result:


```plain text
["9876543210", "9123456789"]
```


---


### Step 3 – Build SOS message


```dart
String message =
"SOS! I need help! My location: https://maps.google.com/?q=${position.latitude},${position.longitude}";
```


Explanation:


Creates a message that includes a Google Maps link pointing to the user's coordinates.


Example message:


```plain text
SOS! I need help!
My location: https://maps.google.com/?q=13.0827,80.2707
```


---


### Step 4 – Create SMS URI


```dart
final smsUri = Uri(
  scheme: 'sms',
  path: contacts.join(','),
  queryParameters: {
    'body': message,
  },
);
```


Explanation:


Constructs a special URI that opens the device’s SMS application.


Example URI:


```plain text
sms:9876543210,9123456789?body=SOS message
```


---


### Step 5 – Launch the SMS application


```dart
await launchUrl(smsUri);
```


Explanation:


This opens the native SMS application with recipients and message pre-filled.


The user confirms and sends the message manually.


---


# 3. Emergency Contact Storage


Package used: `shared_preferences`


Purpose:


Store emergency contacts locally on the device.


---


### Saving contacts


```dart
SharedPreferences prefs = await SharedPreferences.getInstance();

await prefs.setStringList(
  "contacts",
  contacts.map((c) => "${c.name}|${c.phone}").toList(),
);
```


Explanation:


Contacts are converted into a string format and stored locally.


Example stored value:


```plain text
["John|9876543210", "Alice|9123456789"]
```


---


### Loading contacts


```dart
SharedPreferences prefs = await SharedPreferences.getInstance();

List<String>? storedContacts = prefs.getStringList("contacts");
```


Explanation:


Retrieves stored contacts when the application starts.


These values are then converted back into contact objects.


---


# 4. Offline Capability


The application is designed to operate without internet.


Offline features:


GPS retrieval


SMS messaging


Local contact storage


Internet is only required if the recipient opens the Google Maps link.


The coordinates themselves remain usable even without internet access.

