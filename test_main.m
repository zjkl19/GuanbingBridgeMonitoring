
%batch_unzip_data_parallel('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-20',true)
%batch_rename_csv('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25',true);
%batch_remove_header('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25',true);
%batch_resample_data_parallel('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25', 100,true,'batch_resample_data_parallel_config.csv');

%plot_temperature_point_curve('G:\\BaiduNetdiskDownload\\管柄大桥数据','GB-RTS-G05-001-01','2025-02-26', '2025-03-25')

%root = 'G:/BaiduNetdiskDownload/管柄大桥数据';
%pts = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
%analyze_temperature_points(root, pts, '2025-02-26','2025-03-25','temp_stats.xlsx');

%root = 'G:/BaiduNetdiskDownload/管柄大桥数据/';
%pts  = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
%pts  = {'GB-RHS-G05-001-03'};
%analyze_humidity_points(root, pts, '2025-02-26','2025-03-25','humidity_stats.xlsx');

root = 'G:/BaiduNetdiskDownload/管柄大桥数据/';
analyze_tilt_points(root, '2025-02-26','2025-03-25','tilt_stats.xlsx','波形_重采样');
