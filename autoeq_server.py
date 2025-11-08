#!/usr/bin/env python3
"""
AutoEQ Local Server
Локальний сервер для точного обчислення GraphicEQ значень з використанням офіційної AutoEQ бібліотеки
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import sys
import os
import numpy as np

# Додаємо шлях до AutoEQ бібліотеки
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'autoeq'))

from autoeq.frequency_response import FrequencyResponse

app = Flask(__name__)
CORS(app)  # Дозволяємо CORS для локальних запитів

# Центральні частоти для 10-band та 31-band еквалайзерів
BAND_10_FREQS = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
BAND_31_FREQS = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 
                 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 
                 10000, 12500, 16000, 20000]

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'message': 'AutoEQ server is running'})

@app.route('/equalize', methods=['POST'])
def equalize():
    """
    Обчислює GraphicEQ значення для заданих параметрів
    
    Request JSON:
    {
        "measurement_name": "oratory1990/over-ear/Sennheiser HD 800 S",
        "target_name": "JM-1 with Harman filters",
        "band_count": 10 або 31
    }
    
    Response JSON:
    {
        "bands": [{"freq": 31.5, "gain": 2.5}, ...],
        "preamp": -6.5
    }
    """
    try:
        data = request.get_json()
        
        measurement_name = data.get('measurement_name')
        target_name = data.get('target_name', 'JM-1 with Harman filters')
        band_count = data.get('band_count', 10)
        
        if not measurement_name:
            return jsonify({'error': 'measurement_name is required'}), 400
        
        # Визначаємо шляхи до файлів
        base_path = os.path.join(os.path.dirname(__file__), 'AutoEq')
        
        # Шлях до CSV файлу з вимірюваннями (містить raw дані)
        csv_filename = measurement_name.split('/')[-1] + '.csv'
        measurement_dir = os.path.join(base_path, 'results', measurement_name)
        csv_path = os.path.join(measurement_dir, csv_filename)
        
        target_path = os.path.join(base_path, 'targets', f'{target_name}.csv')
        
        # Перевіряємо існування файлів
        if not os.path.exists(csv_path):
            return jsonify({'error': f'Measurement CSV not found: {csv_path}'}), 404
        
        if not os.path.exists(target_path):
            return jsonify({'error': f'Target not found: {target_name}'}), 404
        
        print(f"Loading measurement from: {csv_path}")
        print(f"Loading target from: {target_path}")
        
        # Завантажуємо CSV файли
        import pandas as pd
        
        # Читаємо вимірювання
        df_measurement = pd.read_csv(csv_path)
        freq = df_measurement['frequency'].values
        # Використовуємо raw дані (autoeq.app може використовувати raw)
        raw = df_measurement['raw'].values
        print("DEBUG: Using raw data")
        
        # Читаємо JM-1 target
        df_target = pd.read_csv(target_path, sep=',', skiprows=1, names=['frequency', 'target'])
        target_freq = df_target['frequency'].values
        target_spl = df_target['target'].values
        
        print(f"DEBUG: Loaded {len(raw)} measurement points")
        print(f"DEBUG: Loaded {len(target_spl)} target points")
        
        # Створюємо FrequencyResponse об'єкти
        fr = FrequencyResponse(name=measurement_name, frequency=freq, raw=raw)
        fr.interpolate()
        
        target = FrequencyResponse(name=target_name, frequency=target_freq, raw=target_spl)
        target.interpolate()
        target.center()
        
        # Визначаємо центральні частоти
        center_freqs = BAND_10_FREQS if band_count == 10 else BAND_31_FREQS
        
        # Компенсуємо target
        fr.compensate(target, min_mean_error=True)
        
        # Створюємо еквалізацію
        fr.equalize(
            max_gain=30.0,
            max_slope=50.0,
            window_size=1/12,
            treble_window_size=2.0,
            treble_f_lower=6000.0,
            treble_f_upper=8000.0,
            treble_gain_k=1.0
        )
        
        # Використовуємо optimize_fixed_band_eq як autoeq.app
        # Формат як в PEQ_CONFIGS['10_BAND_GRAPHIC_EQ']
        config = {
            'optimizer': {'min_std': 0.01},
            'filter_defaults': {
                'q': 1.41,  # sqrt(2)
                'min_gain': -30.0,  # Збільшили діапазон
                'max_gain': 30.0,
                'type': 'PEAKING'  # Рядок, не клас!
            },
            'filters': [
                {
                    'fc': float(fc),
                    'min_fc': float(fc),  # Фіксуємо частоту
                    'max_fc': float(fc)
                }
                for fc in center_freqs
            ]
        }
        
        print(f"DEBUG: Calling optimize_fixed_band_eq with {len(config['filters'])} filters...")
        
        # Оптимізуємо фільтри
        peqs = fr.optimize_fixed_band_eq(
            configs=config,
            fs=44100
        )
        
        print(f"DEBUG: Optimization complete, {len(peqs[0].filters)} filters")
        peq_max_gain = peqs[0].max_gain
        
        # Формуємо результат з оптимізованих фільтрів
        bands = []
        
        for i, filt in enumerate(peqs[0].filters):
            print(f"DEBUG: {filt.fc} Hz: gain={filt.gain:.2f}")
            
            bands.append({
                'freq': float(filt.fc),
                'gain': float(filt.gain)
            })
        
        # Обчислюємо preamp
        max_gain = max(band['gain'] for band in bands)
        preamp = -(max_gain + 0.5)
        
        return jsonify({
            'bands': bands,
            'preamp': float(preamp),
            'measurement_name': measurement_name,
            'target_name': target_name
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("Starting AutoEQ Local Server...")
    print("Server will be available at http://localhost:5555")
    app.run(host='127.0.0.1', port=5555, debug=False)
