#!/usr/bin/env python3
"""
Простий скрипт для перерахунку Fixed Band EQ з Harman на JM-1 target
Використовує CSV файл з AutoEQ та target криві
"""
import sys
import csv
import numpy as np
from scipy import interpolate
from scipy.optimize import minimize

# JM-1 target curve (frequency, gain in dB)
JM1_TARGET = [
    (20, 4.538), (31.5, 4.568), (63, 4.109), (125, 1.03), (250, 1.129),
    (500, 0.92), (1000, 1.623), (2000, 1.052), (4000, -0.371),
    (8000, 7.667), (16000, 20.056)
]

# Harman target curve (frequency, gain in dB)
HARMAN_TARGET = [
    (20, 3.86), (31.5, 3.921), (63, 2.909), (125, 0.3), (250, 0.0),
    (500, 0.0), (1000, 0.0), (2000, 0.0), (4000, 0.0),
    (8000, 0.0), (16000, 0.0)
]

# 10-band center frequencies
CENTER_FREQS = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

def load_csv(csv_path):
    """Завантажує frequency response з CSV"""
    freqs = []
    raw = []
    
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            freqs.append(float(row['frequency']))
            raw.append(float(row['raw']))
    
    return np.array(freqs), np.array(raw)

def get_target_gain(freq, target_curve):
    """Інтерполює target gain для заданої частоти"""
    target_freqs = [p[0] for p in target_curve]
    target_gains = [p[1] for p in target_curve]
    f = interpolate.interp1d(target_freqs, target_gains, kind='linear', fill_value='extrapolate')
    return float(f(freq))

def peaking_filter_response(freq, fc, q, gain, fs=48000):
    """Обчислює frequency response peaking фільтра"""
    A = 10 ** (gain / 40)
    w0 = 2 * np.pi * fc / fs
    alpha = np.sin(w0) / (2 * q)
    
    b0 = 1 + alpha * A
    b1 = -2 * np.cos(w0)
    b2 = 1 - alpha * A
    a0 = 1 + alpha / A
    a1 = -2 * np.cos(w0)
    a2 = 1 - alpha / A
    
    # Інвертуємо a1, a2
    a1 *= -1
    a2 *= -1
    
    # Обчислюємо response
    w = 2 * np.pi * freq / fs
    phi = 4 * np.sin(w / 2) ** 2
    
    numerator = (b0 + b1 + b2) ** 2 + (b0 * b2 * phi - (b1 * (b0 + b2) + 4 * b0 * b2)) * phi
    denominator = (a0 + a1 + a2) ** 2 + (a0 * a2 * phi - (a1 * (a0 + a2) + 4 * a0 * a2)) * phi
    
    return 10 * np.log10(numerator) - 10 * np.log10(denominator)

def optimize_fixed_band_eq(freqs, raw, target_curve):
    """Оптимізує 10-band Fixed Band EQ для target curve"""
    
    def objective(gains):
        # Обчислюємо результат застосування всіх фільтрів
        result = np.copy(raw)
        for i, (fc, gain) in enumerate(zip(CENTER_FREQS, gains)):
            q = 1.41  # Стандартне Q для graphic EQ
            filter_response = np.array([peaking_filter_response(f, fc, q, gain) for f in freqs])
            result += filter_response
        
        # Обчислюємо target
        target = np.array([get_target_gain(f, target_curve) for f in freqs])
        
        # Мінімізуємо різницю
        error = np.sum((result - target) ** 2)
        return error
    
    # Початкове наближення - нулі
    x0 = np.zeros(len(CENTER_FREQS))
    
    # Оптимізація
    result = minimize(objective, x0, method='BFGS', options={'maxiter': 100})
    
    return result.x

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 autoeq_jm1.py <path_to_csv>")
        sys.exit(1)
    
    csv_path = sys.argv[1]
    
    # Завантажуємо дані
    freqs, raw = load_csv(csv_path)
    
    # Оптимізуємо для JM-1
    gains = optimize_fixed_band_eq(freqs, raw, JM1_TARGET)
    
    # Виводимо результат
    print("# Fixed Band EQ for JM-1 target")
    print(f"Preamp: {-max(gains) - 0.5:.1f} dB")
    print()
    for fc, gain in zip(CENTER_FREQS, gains):
        print(f"{fc} Hz: {gain:.1f} dB")

if __name__ == '__main__':
    main()
