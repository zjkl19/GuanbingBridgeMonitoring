function [start_date, end_date] = get_start_and_end_date_large_file(file_path)
% get_start_and_end_date_large_file  Compatibility wrapper for CSV date range.

    [start_date, end_date] = bms.data.LargeCsvService.dateRangeLargeFile(file_path);
end
