classdef GuiStatusPanel < handle
    %GUISTATUSPANEL Owns status label, result summary table and log area.

    properties (Access = private)
        StatusLabel
        SummaryTable
        LogArea
        PrimaryColor
    end

    methods
        function obj = GuiStatusPanel(statusLabel, summaryTable, logArea, primaryColor)
            obj.StatusLabel = statusLabel;
            obj.SummaryTable = summaryTable;
            obj.LogArea = logArea;
            if nargin < 4 || isempty(primaryColor)
                primaryColor = [0 94 172] / 255;
            end
            obj.PrimaryColor = primaryColor;
        end

        function clearLog(obj)
            obj.LogArea.Value = cell(0, 1);
        end

        function addLog(obj, msg)
            val = obj.LogArea.Value;
            if ischar(val), val = {val}; end
            if isempty(val), val = {}; end
            val{end+1} = sprintf('[%s] %s', datestr(now, 'HH:MM:SS'), char(string(msg))); %#ok<AGROW>
            obj.LogArea.Value = val;
            drawnow;
        end

        function setReady(obj, message)
            if nargin < 2 || isempty(message), message = '就绪'; end
            obj.setStatus(message, obj.PrimaryColor);
        end

        function setRunning(obj, message)
            if nargin < 2 || isempty(message), message = '运行中...'; end
            obj.setStatus(message, obj.PrimaryColor);
        end

        function setCompleted(obj, elapsed)
            obj.setStatus(sprintf('完成，用时 %.2f 秒', elapsed), [0 0.5 0]);
        end

        function setFailed(obj, message)
            if nargin < 2 || isempty(message), message = '失败'; end
            obj.setStatus(message, [0.8 0 0]);
        end

        function setPendingModules(obj, opts)
            rows = bms.gui.GuiStatusPanel.pendingRowsFromOptions(opts);
            if isempty(rows)
                rows = {'未选择模块', '待运行', '', '', '', '', '请勾选需要执行的模块'};
            end
            obj.SummaryTable.Data = rows;
        end

        function summary = refreshFromRoot(obj, resultRoot, logDetails)
            if nargin < 3, logDetails = false; end
            try
                summary = bms.gui.GuiResultSummary.fromResultRoot(resultRoot);
                obj.applySummary(summary, resultRoot);
                if logDetails
                    obj.logSummary(summary);
                end
            catch ME
                summary = struct('available', false, 'lines', {{['结果摘要读取失败: ' ME.message]}});
                obj.SummaryTable.Data = {'结果摘要读取失败', 'error', '', '', '', class(ME), ME.message};
                if logDetails
                    obj.addLog(['结果摘要读取失败: ' ME.message]);
                end
            end
        end

        function applySummary(obj, summary, resultRoot)
            if isstruct(summary) && isfield(summary, 'available') && summary.available
                obj.setSummaryStatus(summary);
                rows = summary.module_rows;
                if isempty(rows)
                    rows = {'未发现模块记录', char(string(summary.status)), '', '', '', '', char(string(summary.path))};
                end
                obj.SummaryTable.Data = rows;
                return;
            end
            if nargin < 3 || isempty(resultRoot), resultRoot = ''; end
            obj.setStatus('No analysis manifest', [0.55 0.35 0]);
            obj.SummaryTable.Data = {'未找到运行结果', 'missing', '', '', '', '', ...
                ['未找到 analysis_manifest_*.json: ' char(string(resultRoot))]};
        end

        function logSummary(obj, summary)
            if ~isstruct(summary) || ~isfield(summary, 'lines')
                return;
            end
            for i = 1:numel(summary.lines)
                obj.addLog(['结果摘要: ' char(summary.lines{i})]);
            end
        end
    end

    methods (Access = private)
        function setStatus(obj, message, color)
            obj.StatusLabel.Text = char(string(message));
            obj.StatusLabel.FontColor = color;
            drawnow;
        end

        function setSummaryStatus(obj, summary)
            status = char(string(summary.status));
            switch lower(status)
                case {'ok', 'success'}
                    color = [0 0.5 0];
                case {'failed', 'fail', 'error'}
                    color = [0.8 0 0];
                case {'warning'}
                    color = [0.75 0.45 0];
                otherwise
                    color = obj.PrimaryColor;
            end
            counts = summary.counts;
            preflightCount = 0;
            staleCount = 0;
            if isfield(summary, 'preflight_warning_count'), preflightCount = preflightCount + summary.preflight_warning_count; end
            if isfield(summary, 'preflight_error_count'), preflightCount = preflightCount + summary.preflight_error_count; end
            if isfield(summary, 'possible_stale_count'), staleCount = summary.possible_stale_count; end
            msg = sprintf('运行结果%s：正常=%d，失败=%d，缺失=%d，预检提示=%d，疑似旧结果=%d，产物=%d', ...
                bms.gui.GuiResultSummary.displayStatus(status), counts.ok, counts.fail, counts.missing, preflightCount, staleCount, summary.artifact_count);
            obj.setStatus(msg, color);
        end
    end

    methods (Static)
        function rows = pendingRowsFromOptions(opts)
            rows = {};
            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            for i = 1:numel(specs)
                if strcmp(specs(i).Category, 'postprocess')
                    continue;
                end
                rows(end+1, :) = {specs(i).Label, '待运行', '', '', '', '', ''}; %#ok<AGROW>
            end
        end
    end
end
