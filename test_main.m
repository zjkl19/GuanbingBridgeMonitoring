
%batch_unzip_data_parallel('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-03-20', '2025-03-31')
batch_rename_csv('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-03-25', '2025-03-26');
%batch_resample_wave_data('F:/管柄大桥健康监测数据/', '2025-03-26', '2025-03-26', 100);
%batch_remove_wave_header('F:/管柄大桥健康监测数据/', '2025-03-27', '2025-03-27');

