
tic;
%root = 'G:/BaiduNetdiskDownload/管柄大桥数据';
root = 'H:\BaiduNetdiskDownload\';
start_date  = '2025-03-26';
end_date    = '2025-04-25';
warnState = warning('off','MATLAB:table:ModifiedAndSavedVarnames');   %临时关闭读取表格的警告

batch_unzip_data_parallel(root, start_date, end_date,true)
batch_rename_csv(root, start_date, end_date,true);
batch_remove_header('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25',true);
batch_resample_data_parallel(root, start_date, end_date, 100,true,'batch_resample_data_parallel_config.csv');

pts = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
analyze_temperature_points(root, pts , start_date, end_date,'temp_stats.xlsx','特征值');

pts  = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
analyze_humidity_points(root, pts, start_date,end_date,'humidity_stats.xlsx','特征值');

useMedianFilter = false; 
analyze_deflection_points(root,start_date,end_date,'deflection_stats.xlsx','特征值',useMedianFilter);

useMedianFilter = true; 
analyze_deflection_points(root,start_date,end_date,'deflection_中值滤波_stats.xlsx','特征值',useMedianFilter);

analyze_tilt_points(root, start_date,end_date,'tilt_stats.xlsx','波形_重采样');

analyze_acceleration_points(root, start_date,end_date,'accel_stats.xlsx','波形_重采样',true);

batch_rename_crk_T_to_t(root, start_date, end_date, true);

analyze_crack_points(root, start_date,end_date,'crack_stats.xlsx','特征值');

analyze_strain_points(root,  start_date, end_date,'strain_stats.xlsx','特征值')

warning(warnState);  %恢复读取表格的警告

toc;
