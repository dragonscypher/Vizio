# Vizio

Vizio is a project that combines SLAM with small language models to provide real-time navigation assistance and situational descriptions for visually impaired users. Initially designed to run on pre-recorded video (with plans to migrate to wearable glasses), Vizio integrates:

- **SLAM Module:** For mapping and localization.
- **Computer Vision:** For object and face detection.
- **Language Model:** A lightweight reasoning engine (e.g., Mistral) to generate context-aware feedback.
- **Speech Module:** Offline text-to-speech (TTS) for verbal feedback.

## Project Structure

Vizio/ ├── README.md ├── requirements.txt ├── config/ │ └── config.yaml ├── data/ │ └── videos/ # Place your pre-recorded videos here. ├── models/ │ ├── slam/ # SLAM-related models/configurations. │ ├── object_detection/ # Object detection model files. │ ├── face_detection/ # Face detection/recognition model files. │ └── language_model/ # Small language model (e.g., Mistral) files. ├── modules/ │ ├── init.py │ ├── video_input.py # Video ingestion. │ ├── slam.py # SLAM processing. │ ├── vision.py # Object & face detection. │ ├── language.py # Reasoning and instruction generation. │ └── speech.py # Offline text-to-speech. └── main.py # Main control loop.


## Installation

1. Clone the repository:
   ```bash
   git clone https://your-repo-url.git
   cd Vizio

    Create a virtual environment and install dependencies:

    python -m venv venv
    source venv/bin/activate  # On Windows use: venv\Scripts\activate
    pip install -r requirements.txt

    Update the config/config.yaml as needed.

Running the Project

To run Vizio with a pre-recorded video, execute:

```bash
python main.py
```


---

### File: requirements.txt

```txt
opencv-python
numpy
pyyaml
pyttsx3
torch
