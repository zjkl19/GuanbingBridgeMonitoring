function normalized_displacement = analyze_vibration_mode_large_files(file_paths, start_time, end_time, frequency, sampling_rate)
% analyze_vibration_mode_large_files  Compatibility wrapper for vibration modes.

    normalized_displacement = bms.analyzer.VibrationModeService.analyzeLargeFiles( ...
        file_paths, start_time, end_time, frequency, sampling_rate);
end
