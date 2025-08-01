


%analyze_accel_spectrum_points(root_dir,start_date,end_date,point_ids, ...
%                                       excel_file,subfolder,target_freqs,tolerance, ...
%                                       use_parallel)
root        = 'F:\管柄数据\管柄测试数据';

start_date  = '2025-06-05';
end_date    = '2025-06-06';

point_ids = { ...
    'GB-VIB-G04-001-01','GB-VIB-G05-001-01','GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
    'GB-VIB-G06-001-01','GB-VIB-G06-002-01','GB-VIB-G06-003-01','GB-VIB-G07-001-01'};

excel_file='accel_spec_stats.xlsx';

subfolder  = '波形';
target_freqs=[1.150 1.480 2.310];
tolerance  = 0.15;

analyze_accel_spectrum_points(root ,start_date, end_date,point_ids, ...
    excel_file,subfolder,target_freqs,tolerance, ...
    true)