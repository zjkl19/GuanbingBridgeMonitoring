function run_all(root, start_date, end_date, opts)
    tic;
    % 关闭读取表格时那条“ModifiedAndSavedVarnames”警告
    ws = warning('off','MATLAB:table:ModifiedAndSavedVarnames');
    
    if opts.doUnzip
        batch_unzip_data_parallel(root, start_date, end_date, true);
    end

    if opts.doRenameCsv
        batch_rename_csv(root, start_date, end_date, true);
    end

    if opts.doRemoveHeader
        batch_remove_header(root, start_date, end_date, true);
    end

    if opts.doResample
        batch_resample_data_parallel(...
            root, start_date, end_date, 100, true, 'batch_resample_data_parallel_config.csv');
    end

    if opts.doTemp
        pts = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
        analyze_temperature_points(root, pts, start_date, end_date, 'temp_stats.xlsx', '特征值');
    end

    if opts.doHumidity
        pts = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
        analyze_humidity_points(root, pts, start_date, end_date, 'humidity_stats.xlsx', '特征值');
    end

    if opts.doDeflect
        analyze_deflection_points(root, start_date, end_date, ...
            'deflection_stats.xlsx', '特征值');
    end

    if opts.doTilt
        analyze_tilt_points(root, start_date, end_date, 'tilt_stats.xlsx', '波形_重采样');
    end
    if opts.doAccel
        analyze_acceleration_points(root, start_date, end_date, ...
            'accel_stats.xlsx', '波形_重采样', true);
    end

    if opts.doRenameCrk
        batch_rename_crk_T_to_t(root, start_date, end_date, true);
    end
    if opts.doCrack
        analyze_crack_points(root, start_date, end_date, 'crack_stats.xlsx', '特征值');
    end
    if opts.doStrain
        analyze_strain_points(root, start_date, end_date, 'strain_stats.xlsx', '特征值');
    end

    % 恢复警告
    warning(ws);
    fprintf('总耗时: %.2f 秒\n', toc);
end
