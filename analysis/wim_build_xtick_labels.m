function labels = wim_build_xtick_labels(xlabels, yvals, show_pct, percent_on_newline)
% wim_build_xtick_labels  Build tick labels with optional percent display.

    labels = cellstr(string(xlabels));
    if ~show_pct
        return;
    end
    total = sum(yvals);
    if total <= 0
        return;
    end
    pct = yvals ./ total * 100;
    n = numel(xlabels);
    labels = cell(n,1);
    for i = 1:n
        if percent_on_newline
            labels{i} = sprintf('%s\n(%.2f%%)', char(string(xlabels(i))), pct(i));
        else
            labels{i} = sprintf('%s (%.2f%%)', char(string(xlabels(i))), pct(i));
        end
    end
end
