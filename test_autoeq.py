#!/usr/bin/env python3
"""
Тестуємо формулу AutoEQ для LowShelf фільтра
"""
import numpy as np

# Параметри з твого DEBUG
fc = 105.0
q = 0.7
gain = 6.3
fs = 48000.0
f = 31.5  # Частота на якій обчислюємо

# Обчислюємо коефіцієнти
w0 = 2 * np.pi * fc / fs
A = 10 ** (gain / 40)
alpha = np.sin(w0) / (2 * q)

print(f"Параметри:")
print(f"  fc={fc}, q={q}, gain={gain}")
print(f"  f={f} Hz")
print(f"  A={A}")
print(f"  w0={w0}")
print(f"  alpha={alpha}")
print()

# Low Shelf коефіцієнти (як в AutoEQ peq.py)
a0 = (A + 1) + (A - 1) * np.cos(w0) + 2 * np.sqrt(A) * alpha
a1 = -2 * ((A - 1) + (A + 1) * np.cos(w0))
a2 = (A + 1) + (A - 1) * np.cos(w0) - 2 * np.sqrt(A) * alpha

b0 = A * ((A + 1) - (A - 1) * np.cos(w0) + 2 * np.sqrt(A) * alpha)
b1 = 2 * A * ((A - 1) - (A + 1) * np.cos(w0))
b2 = A * ((A + 1) - (A - 1) * np.cos(w0) - 2 * np.sqrt(A) * alpha)

print(f"Коефіцієнти (до інверсії):")
print(f"  a0={a0}, a1={a1}, a2={a2}")
print(f"  b0={b0}, b1={b1}, b2={b2}")
print()

# Інвертуємо знак a1, a2 (як в AutoEQ)
a1 *= -1
a2 *= -1

print(f"Коефіцієнти (після інверсії):")
print(f"  a0={a0}, a1={a1}, a2={a2}")
print(f"  b0={b0}, b1={b1}, b2={b2}")
print()

# Обчислюємо frequency response
w = 2 * np.pi * f / fs
phi = 4 * np.sin(w / 2) ** 2

numerator = (b0 + b1 + b2) ** 2 + (b0 * b2 * phi - (b1 * (b0 + b2) + 4 * b0 * b2)) * phi
denominator = (a0 + a1 + a2) ** 2 + (a0 * a2 * phi - (a1 * (a0 + a2) + 4 * a0 * a2)) * phi

print(f"Frequency response на {f} Hz:")
print(f"  w={w}")
print(f"  phi={phi}")
print(f"  b0+b1+b2={b0+b1+b2}")
print(f"  a0+a1+a2={a0+a1+a2}")
print(f"  numerator={numerator}")
print(f"  denominator={denominator}")
print()

result = 10 * np.log10(numerator) - 10 * np.log10(denominator)
print(f"РЕЗУЛЬТАТ: {result:.2f} dB")
print()

# Тепер обчислимо для всіх 10 центральних частот
print("=" * 60)
print("Обчислення для всіх 10 смуг:")
print("=" * 60)

center_freqs = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

for center_f in center_freqs:
    w = 2 * np.pi * center_f / fs
    phi = 4 * np.sin(w / 2) ** 2
    
    numerator = (b0 + b1 + b2) ** 2 + (b0 * b2 * phi - (b1 * (b0 + b2) + 4 * b0 * b2)) * phi
    denominator = (a0 + a1 + a2) ** 2 + (a0 * a2 * phi - (a1 * (a0 + a2) + 4 * a0 * a2)) * phi
    
    result = 10 * np.log10(numerator) - 10 * np.log10(denominator)
    print(f"{center_f:>7.1f} Hz: {result:>8.2f} dB")
