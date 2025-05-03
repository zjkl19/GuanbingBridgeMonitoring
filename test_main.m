
%batch_unzip_data_parallel('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-20',true)
%batch_rename_csv('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25',true);
%batch_remove_header('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25',true);
batch_resample_data_parallel('G:\\BaiduNetdiskDownload\\管柄大桥数据', '2025-02-26', '2025-03-25', 100*4,true,'batch_resample_data_parallel_config.csv');


