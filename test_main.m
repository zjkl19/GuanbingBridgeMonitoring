
%batch_unzip_data_parallel('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-20',true)
%batch_rename_csv('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25',true);
%batch_remove_header('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25',true);
%batch_resample_data_parallel('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25', 100,true,'batch_resample_data_parallel_config.csv');

root = 'G:/BaiduNetdiskDownload/管柄大桥数据';
start_date  = '2025-02-26';
end_date    = '2025-03-25';
%pts = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
%analyze_temperature_points(root, pts, '2025-02-26','2025-03-25','temp_stats.xlsx','特征值_重采样');

%pts  = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
%analyze_humidity_points(root, pts, start_date,end_date,'humidity_stats.xlsx','特征值_重采样');

%analyze_deflection_points(root,start_date,end_date,'deflection_stats.xlsx','特征值_重采样');

%analyze_tilt_points(root, start_date,end_date,'tilt_stats.xlsx','波形_重采样');


%root = 'G:/BaiduNetdiskDownload/管柄大桥数据/';
%analyze_acceleration_points(root, '2025-02-26','2025-03-25','accel_stats.xlsx','波形_重采样')

%root = 'G:/BaiduNetdiskDownload/管柄大桥数据/';
%batch_rename_crk_T_to_t(root,'2025-02-26','2025-03-25', true)
%tic;
%root = 'G:/BaiduNetdiskDownload/管柄大桥数据/';
%analyze_crack_points(root, '2025-02-26','2025-03-25','crack_stats.xlsx','特征值')
%toc;

analyze_strain_points(root, '2025-02-26','2025-03-25','strain_stats.xlsx','特征值')

