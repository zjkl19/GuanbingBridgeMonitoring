function data = read_csv_with_header(file_path)
% read_csv_with_header  Compatibility wrapper for legacy large CSV headers.

    data = bms.data.LargeCsvService.readWithHeader(file_path);
end
