classdef test_config_integration_regression < matlab.unittest.TestCase
    methods (Test)
        function fourBridgeConfigsLoadLintAndBuildContracts(tc)
            rootDir = project_root();
            configPaths = { ...
                fullfile(rootDir, 'config', 'default_config.json'), ...
                fullfile(rootDir, 'config', 'hongtang_config.json'), ...
                fullfile(rootDir, 'config', 'jiulongjiang_config.json'), ...
                fullfile(rootDir, 'config', 'shuixianhua_config.json')};

            for i = 1:numel(configPaths)
                cfg = load_config(configPaths{i});
                lint = bms.config.ConfigLinter.lint(cfg);
                tc.verifyEmpty(lint.errors, ['lint errors in ' configPaths{i}]);

                contract = bms.reporting.AnalysisReportingContract.build(cfg, struct());
                tc.verifyGreaterThan(contract.summary.module_count, 0, ...
                    ['empty reporting contract for ' configPaths{i}]);

                root = tempname;
                mkdir(root);
                cleanup = onCleanup(@() cleanup_dir(root)); %#ok<NASGU>
                preflight = bms.app.RunPreflight.check(root, '2026-03-01', '2026-03-02', struct(), cfg);
                tc.verifyEmpty(preflight.errors, ['preflight errors in ' configPaths{i}]);
                tc.verifyTrue(isfield(preflight, 'reporting_contract'));
                clear cleanup;
            end
        end
    end
end

function cleanup_dir(path)
    if isfolder(path)
        rmdir(path, 's');
    end
end

function root = project_root()
    root = fileparts(fileparts(mfilename('fullpath')));
end
