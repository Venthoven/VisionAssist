from ultralytics import YOLO

model = YOLO("yolov8n.onnx")
results = model("test.jpg")

results[0].show()