#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <iostream>
#include <cmath>
#include <thread>
#include <chrono>
// g++ -o miniaudio_test CRACK/CR_PROG/ADDIT/1.CPP -I/mnt/c/Users/Margarita  -lm -ldl -lpthread -lpulse
// Функция генерации синусоиды
void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    float* output = (float*)pOutput;
    static double phase = 0.0;
    const double phaseIncrement = 2.0 * 3.14159 * 440.0 / 48000.0; // 440 Hz
    
    for (ma_uint32 i = 0; i < frameCount; i++) {
        float sample = (float)(sin(phase) * 0.5); // Амплитуда 0.5
        output[i*2] = sample;     // Левый канал
        output[i*2+1] = sample;   // Правый канал
        phase += phaseIncrement;
    }
}

int main() {
    std::cout << "=== Miniaudio Test ===" << std::endl;
    std::cout << "PULSE_SERVER = " << (getenv("PULSE_SERVER") ? getenv("PULSE_SERVER") : "не установлен") << std::endl;
    
    // Конфигурация устройства
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = 2;
    config.sampleRate = 48000;
    config.dataCallback = data_callback;
    config.pUserData = nullptr;
    
    ma_device device;
    
    std::cout << "Инициализация звукового устройства..." << std::endl;
    
    // Инициализация устройства
    if (ma_device_init(NULL, &config, &device) != MA_SUCCESS) {
        std::cerr << "Ошибка: не удалось инициализировать звуковое устройство!" << std::endl;
        return -1;
    }
    
    std::cout << "Устройство инициализировано: " << device.playback.name << std::endl;
    std::cout << "Частота: " << device.sampleRate << " Hz" << std::endl;
    std::cout << "Каналы: " << device.playback.channels << std::endl;
    
    std::cout << "\nВоспроизведение звука 440 Hz в течение 3 секунд..." << std::endl;
    
    // Запуск воспроизведения
    if (ma_device_start(&device) != MA_SUCCESS) {
        std::cerr << "Ошибка: не удалось запустить воспроизведение!" << std::endl;
        ma_device_uninit(&device);
        return -1;
    }
    
    // Ждем 3 секунды
    std::this_thread::sleep_for(std::chrono::seconds(3));
    
    // Остановка и очистка
    ma_device_stop(&device);
    ma_device_uninit(&device);
    
    std::cout << "Тест завершен!" << std::endl;
    return 0;
}