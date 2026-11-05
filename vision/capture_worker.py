"""Native camera calls run only in a disposable child process."""
import time
import cv2
import numpy as np

def capture_worker(config, stop, lock, pixels, header, status, factory=None):
    cv2.setNumThreads(1)
    capacity = len(pixels)
    image_buffer = np.frombuffer(pixels, dtype=np.uint8)
    backend = {"dshow": cv2.CAP_DSHOW, "msmf": cv2.CAP_MSMF, "auto": cv2.CAP_ANY}[config.backend]

    def publish(message, opened=False):
        with lock:
            encoded = message.encode("utf-8", errors="replace")[:510]
            status.value = encoded
            header[6] = int(opened)
            header[7] = time.monotonic()

    while not stop.is_set():
        camera = None
        try:
            publish(f"CAMERA {config.index} opening")
            opened_at = time.monotonic()
            camera = (factory or cv2.VideoCapture)(config.index, backend)
            header[10] = (time.monotonic()-opened_at)*1000
            if not camera.isOpened():
                publish(f"CAMERA {config.index}: cannot open; retrying")
            else:
                camera.set(cv2.CAP_PROP_FRAME_WIDTH, config.width)
                camera.set(cv2.CAP_PROP_FRAME_HEIGHT, config.height)
                camera.set(cv2.CAP_PROP_FPS, config.fps)
                publish("CAMERA connected", True)
                while not stop.is_set():
                    started = time.monotonic()
                    header[7] = started
                    ok, image = camera.read()
                    captured_at = time.monotonic()
                    if not ok or image is None or image.size == 0:
                        header[11] += 1
                        publish("CAMERA disconnected/read error; retrying")
                        break
                    if image.ndim != 3 or image.shape[2] != 3 or image.dtype != np.uint8 or image.size > capacity:
                        publish("CAMERA unsupported frame format/size")
                        break
                    if config.mirror:
                        image = cv2.flip(image, 1)
                    with lock:
                        image_buffer[:image.size] = image.reshape(-1)
                        header[0] += 1
                        header[1:6] = [captured_at, image.shape[1], image.shape[0], 3, (captured_at-started)*1000]
                        header[6] = 1
                        header[7] = captured_at
                    stop.wait(max(0, 1/config.fps-(time.monotonic()-started)))
        except (cv2.error, OSError, RuntimeError) as error:
            publish(f"CAMERA error: {error}")
        finally:
            if camera is not None:
                camera.release()
            header[6] = 0
        stop.wait(config.reconnect_delay)
    publish("CAMERA closed")
