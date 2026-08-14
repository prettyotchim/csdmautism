import os
import wave
import struct

def amplify_wav(filepath, factor=3.0):
    try:
        with wave.open(filepath, 'rb') as wav_in:
            params = wav_in.getparams()
            nchannels, sampwidth, framerate, nframes, comptype, compname = params
            
            # Мы работаем только с 16-битными файлами
            if sampwidth != 2:
                print(f"Пропуск {filepath}: файл не 16-bit")
                return
                
            frames = wav_in.readframes(nframes)
            
        # Распаковываем как 16-битные целые числа со знаком (little-endian)
        count = len(frames) // 2
        samples = struct.unpack(f"<{count}h", frames)
        
        # Увеличиваем громкость и ограничиваем (чтобы не было жесткого хрипа)
        new_samples = []
        for s in samples:
            val = int(s * factor)
            if val > 32767: val = 32767
            elif val < -32768: val = -32768
            new_samples.append(val)
            
        # Упаковываем обратно
        new_frames = struct.pack(f"<{count}h", *new_samples)
        
        # Сохраняем во временный файл и заменяем оригинал
        temp_path = filepath + ".tmp"
        with wave.open(temp_path, 'wb') as wav_out:
            wav_out.setparams(params)
            wav_out.writeframes(new_frames)
            
        os.replace(temp_path, filepath)
        print(f"Громкость увеличена (x{factor}): {filepath}")
        
    except Exception as e:
        print(f"Ошибка при обработке {filepath}: {e}")

if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))
    for root, dirs, files in os.walk(current_dir):
        for f in files:
            if f.lower().endswith(".wav"):
                amplify_wav(os.path.join(root, f), 3.0) # Увеличиваем в 3 раза
