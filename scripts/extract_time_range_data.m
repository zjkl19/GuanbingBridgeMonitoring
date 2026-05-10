function data = extract_time_range_data(file_path, start_time, end_time)
% extract_time_range_data  Compatibility wrapper for large CSV time slices.

    data = bms.data.LargeCsvService.extractTimeRange(file_path, start_time, end_time);
end
