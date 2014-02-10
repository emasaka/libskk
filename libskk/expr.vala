/*
 * Copyright (C) 2011-2012 Daiki Ueno <ueno@unixuser.org>
 * Copyright (C) 2011-2012 Red Hat, Inc.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
using Gee;

namespace Skk {
    enum ExprNodeType {
        ARRAY,
        SYMBOL,
        STRING,
        NUMBER
    }

    struct ExprNode {
        public ExprNodeType type;
        public LinkedList<ExprNode?> nodes;
        public string data;
        public int number;
    }

    private ExprNode array_node (LinkedList<ExprNode?> ary) {
        return ExprNode () { type = ExprNodeType.ARRAY, nodes = ary };
    }

    private ExprNode symbol_node (string str) {
        return ExprNode () { type = ExprNodeType.SYMBOL, data = str };
    }

    private ExprNode string_node (string str) {
        return ExprNode () { type = ExprNodeType.STRING, data = str };
    }

    private ExprNode number_node (int num) {
        return ExprNode () { type = ExprNodeType.NUMBER, number = num };
    }

    class ExprReader : Object {
        public ExprNode read_symbol (string expr, ref int index) {
            var builder = new StringBuilder ();
            bool stop = false;
            unichar uc = '\0';
            while (!stop && expr.get_next_char (ref index, out uc)) {
                switch (uc) {
                case '\\':
                    if (expr.get_next_char (ref index, out uc)) {
                        builder.append_unichar (uc);
                    }
                    break;
                case '(': case ')': case '"': case ' ':
                    index--;
                    stop = true;
                    break;
                default:
                    builder.append_unichar (uc);
                    break;
                }
            }
            return symbol_node (builder.str);
        }

        public ExprNode? read_string (string expr, ref int index) {
            return_val_if_fail (index < expr.length && expr[index] == '"',
                                null);
            var builder = new StringBuilder ();
            index++;
            bool stop = false;
            unichar uc = '\0';
            while (!stop && expr.get_next_char (ref index, out uc)) {
                switch (uc) {
                case '\\':
                    if (expr.get_next_char (ref index, out uc)) {
                        switch (uc) {
                        case '0':
                            int num = 0;
                            while (expr.get_next_char (ref index, out uc)) {
                                if (uc < '0' || uc > '7')
                                    break;
                                num <<= 3;
                                num += (int) uc - '0';
                            }
                            index--;
                            uc = (unichar) num;
                            break;
                        case 'x':
                            int num = 0;
                            while (expr.get_next_char (ref index, out uc)) {
                                uc = uc.tolower ();
                                if (('0' <= uc && uc <= '9') ||
                                    ('a' <= uc && uc <= 'f')) {
                                    num <<= 4;
                                    if ('0' <= uc && uc <= '9') {
                                        num += (int) uc - '0';
                                    }
                                    else if ('a' <= uc && uc <= 'f') {
                                        num += (int) uc - 'a' + 10;
                                    }
                                }
                                else {
                                    break;
                                }
                            }
                            index--;
                            uc = (unichar) num;
                            break;
                        default:
                            break;
                        }
                        builder.append_unichar (uc);
                    }
                    break;
                case '\"':
                    stop = true;
                    break;
                default:
                    builder.append_unichar (uc);
                    break;
                }
            }
            return string_node (builder.str);
        }

        public ExprNode read_number (string expr, ref int index) {
            int n = 0;
            unichar uc = '\0';
            while (expr.get_next_char (ref index, out uc)) {
                if ('0' <= uc && uc <= '9') {
                    n = n * 10 + (int) uc - '0';
                } else {
                    index--;
                    break;
                }
            }
            return number_node (n);
        }

        public ExprNode read_character (string expr, ref int index) {
            unichar uc = '\0';
            // FIXME handle escaped characters
            expr.get_next_char (ref index, out uc);
            return number_node ((int) uc);
        }

        public ExprNode? read_array (string expr, ref int index) {
            return_val_if_fail (index < expr.length && expr[index] == '(',
                                null);
            var nodes = new LinkedList<ExprNode?> ();
            bool stop = false;
            index++;
            unichar uc = '\0';
            while (!stop && expr.get_next_char (ref index, out uc)) {
                switch (uc) {
                case ' ':
                    break;
                case ')':
                    stop = true;
                    break;
                default:
                    index--;
                    nodes.add (read_expr (expr, ref index));
                    break;
                }
            }
            return array_node (nodes);
        }

        public ExprNode? read_expr (string expr, ref int index) {
            unichar uc = '\0';
            while (expr.get_next_char (ref index, out uc)) {
                switch (uc) {
                case ' ':
                    break;
                case '(':
                    index--;
                    return read_array (expr, ref index);
                case '"':
                    index--;
                    return read_string (expr, ref index);
                case '0': case '1': case '2': case '3': case '4':
                case '5': case '6': case '7': case '8': case '9':
                    index--;
                    return read_number (expr, ref index);
                case '?':
                    return read_character (expr, ref index);
                default:
                    index--;
                    return read_symbol (expr, ref index);
                }
            }
            // empty expr string -> empty array
            return array_node (new LinkedList<ExprNode?> ());
        }
    }

    class ExprEvaluator : Object {
        private ExprNode? call_lambda (ExprNode lmd,
                                      LinkedList<ExprNode?> params,
                                      Map<string, ExprNode?> env) {
            var new_env = new HashMap<string, ExprNode?> ();
            foreach (var entry in env.entries) {
               new_env.set (entry.key, entry.value);
            }

            var l_iter = lmd.nodes.list_iterator ();
            if (! l_iter.first ()) return null; // skip 'lambda'
            if (! l_iter.next ()) return null;
            var args = l_iter.get ();
            if (args.type != ExprNodeType.ARRAY) return null;
            var a_iter = args.nodes.list_iterator ();
            var p_iter = params.list_iterator ();
            while (a_iter.next ()) {
                if (! p_iter.next ()) return null;
                var arg = a_iter.get ();
                var param = p_iter.get ();
                new_env.set (arg.data, param);
            }

            ExprNode? rtn = symbol_node ("nil");
            while (l_iter.next ()) {
                rtn = _eval (l_iter.get (), new_env);
                if (rtn == null) break;
            }
            return rtn;
        }

        private double skk_assoc_units (string u_from, string u_to) {
            double m = 0;
            if (u_from == "mile") {
                if (u_to == "km") {
                    m = 1.6093;
                }
                else if (u_to == "yard") {
                    m = 1760;
                }
            }
            else if (u_from == "yard") {
                if (u_to == "feet") {
                    m = 3;
                }
                else if (u_to == "cm") {
                    m = 91.44;
                }
            }
            else if (u_from == "feet") {
                if (u_to == "inch") {
                    m = 12;
                }
                else if (u_to == "cm") {
                    m = 30.48;
                }
            }
            else if (u_from == "inch") {
                if (u_to == "feet") {
                    m = 0.5;
                }
                else if (u_to == "cm") {
                    m = 2.54;
                }
            }
            return m;
        }

        struct StrsInt {
            public string[] strs;
            public int num;
        }

        private StrsInt? skk_ad_to_gengo_1 (int ad) {
            if (ad >= 1988) {
                return StrsInt () { strs = {"平成", "H"}, num = ad - 1988 };
            }
            else if (ad >= 1925) {
                return StrsInt () { strs = {"昭和", "S"}, num = ad - 1925 };
            }
            else if (ad >= 1911) {
                return StrsInt () { strs = {"大正", "T"}, num = ad - 1911 };
            }
            else if (ad >= 1867) {
                return StrsInt () { strs = {"明治", "M"}, num = ad - 1867 };
            }
            return null;
        }

        private int skk_gengo_to_ad_1 (string gengo, int y) {
            switch (gengo) {
            case "へいせい":
                return y + 1988;
            case "しょうわ":
                return y + 1925;
            case "たいしょう":
                return y + 1911;
            case "めいじ":
                return y + 1867;
            }
            return -1;
        }

        private int skk_assoc_month (string month) {
            string[] months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                               "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
            for (var i = 0; i < 12; i++) {
                if (month == months[i]) {
                    return i + 1;
                }
            }
            return -1;
        }

        private string? skk_assoc_dow (string dow) {
            string[,] dows = {
                {"Sun", "日"}, {"Mon", "月"}, {"Tue", "火"}, {"Wed", "水"},
                {"Thu", "木"}, {"Fri", "金"}, {"Sat", "土"}};

            for (var i = 0; i < 7; i++) {
                if (dow == dows[i, 0]) {
                    return dows[i, 1];
                }
            }
            return null;
        }

        private ExprNode[]? args_to_array (int n, ListIterator<ExprNode?> iter) {
            ExprNode[] ary = new ExprNode[n];
            for (var i = 0; i < n; i++) {
                if (!iter.next ()) return null;
                ary[i] = iter.get ();
            }
            return ary;
        }

        private LinkedList<ExprNode?> skk_current_date_1 () {
            var dt = new LinkedList<ExprNode?> ();
            var datetime = new DateTime.now_local ();
            dt.add (string_node (datetime.get_year ().to_string ()));
            dt.add (string_node (datetime.format ("%b%")));
            dt.add (string_node (datetime.get_day_of_month ().to_string ()));
            dt.add (string_node (datetime.format ("%a")));
            dt.add (string_node (datetime.get_hour ().to_string ()));
            dt.add (string_node (datetime.get_minute ().to_string ()));
            dt.add (string_node (datetime.get_second ().to_string ()));
            return dt;
        }

        private string? skk_default_current_date (LinkedList<ExprNode?> date_info,
                                                 string? format, int num_type,
                                                 bool gengo_p, int gengo_index,
                                                 int month_index, int dow_index) {
            var iter = date_info.list_iterator ();
            ExprNode[]? dt = args_to_array (4, iter);
            if (dt == null) return null;
            if (dt[0].type != ExprNodeType.STRING) return null;
            if (dt[1].type != ExprNodeType.STRING) return null;
            if (dt[2].type != ExprNodeType.STRING) return null;
            if (dt[3].type != ExprNodeType.STRING) return null;
            // ignore rest arguments

            string? year_str = null;
            int year_i = int.parse (dt[0].data);
            if (gengo_p) {
                var g = skk_ad_to_gengo_1 (year_i);
                year_str = g.strs [gengo_index] +
                    Util.get_numeric (g.num, (NumericConversionType) num_type);
            }
            else {
                year_str = Util.get_numeric (year_i,
                                             (NumericConversionType) num_type);
            }

            string month_str = dt[1].data;
            if (month_index >= 0) {
                int month_i = skk_assoc_month (dt[1].data);
                if (month_i < 0) return null;
                month_str = Util.get_numeric (month_i,
                                              (NumericConversionType) num_type);
            }

            string day_str = Util.get_numeric (int.parse (dt[2].data),
                                               (NumericConversionType) num_type);

            string dow_str = dt[3].data;
            if (dow_index >= 0) {
                var dow2 = skk_assoc_dow (dt[3].data);
                if (dow2 == null) return null;
                dow_str = dow2;
            }

            var builder = new StringBuilder ();
            builder.printf (((format == null) ? "%s年%s月%s日(%s)" : format),
                           year_str, month_str, day_str, dow_str);
            return builder.str;
        }

        private ExprNode? apply (ExprNode func, LinkedList<ExprNode?>? args,
                                Map<string, ExprNode?> env) {
            var iter = args.list_iterator ();

            // FIXME support other functions in more extensible way
            if (func.data == "concat") {
                var builder = new StringBuilder ();
                while (iter.next ()) {
                    var arg = iter.get ();
                    if (arg.type == ExprNodeType.STRING) {
                        builder.append (arg.data);
                    }
                }
                return string_node (builder.str);
            }
            else if (func.data == "current-time-string") {
                var datetime = new DateTime.now_local ();
                return string_node (datetime.format ("%a %b %e %T %Y %z"));
            }
            else if (func.data == "pwd") {
                return string_node (Environment.get_current_dir ());
            }
            else if (func.data == "skk-version") {
                return string_node ("%s/%s".printf (Config.PACKAGE_NAME,
                                                    Config.PACKAGE_VERSION));
            }
            else if (func.data == "make-string") {
                ExprNode[] args_ary = args_to_array (2, iter);
                if (args_ary == null) return null;
                if (args_ary[0].type != ExprNodeType.NUMBER) return null;
                if (args_ary[1].type != ExprNodeType.NUMBER) return null;

                var builder = new StringBuilder ();
                int num = args_ary[0].number;
                unichar c = (unichar) args_ary[1].number;
                for (int i = 0; i < num; i++) {
                    builder.append_unichar (c);
                }
                return string_node (builder.str);
            }
            else if (func.data == "substring") {
                ExprNode[] args_ary = args_to_array (3, iter);
                if (args_ary == null) return null;
                if (args_ary[0].type != ExprNodeType.STRING) return null;
                string text = args_ary[0].data;
                 if (args_ary[1].type != ExprNodeType.NUMBER) return null;
                int offset = args_ary[1].number;
                if (args_ary[2].type != ExprNodeType.NUMBER) return null;

                int len = args_ary[2].number - offset;
                string subtext = text.substring (offset, len);
                return string_node (subtext);
            }
            else if (func.data == "-") {
                ExprNode[] args_ary = args_to_array (2, iter);
                if (args_ary == null) return null;
                if (args_ary[0].type != ExprNodeType.NUMBER) return null;
                if (args_ary[1].type != ExprNodeType.NUMBER) return null;

                return number_node (args_ary[0].number - args_ary[1].number);
            }
            else if (func.data == "car") {
                if (!iter.next ()) return null;
                var lst = iter.get ();
                if (lst.type != ExprNodeType.ARRAY) return null;
                return lst.nodes.first ();
            }
            else if (func.data == "string-to-number") {
                if (!iter.next ()) return null;
                var str = iter.get ();
                if (str.type != ExprNodeType.STRING) return null;
                return number_node (int.parse (str.data));
            }
            else if (func.data == "skk-times") {
                var iter2 = env.get ("skk-num-list").nodes.list_iterator ();
                if (!iter2.next ()) return null;
                var n1 = int.parse (iter2.get ().data);
                if (!iter2.next ()) return null;
                var n2 = int.parse (iter2.get ().data);
                return string_node ((n1 * n2).to_string());
            }
            else if (func.data == "skk-gadget-units-conversion") {
                ExprNode[] args_ary = args_to_array (3, iter);
                if (args_ary == null) return null;
                if (args_ary[0].type != ExprNodeType.STRING) return null;
                if (args_ary[1].type != ExprNodeType.NUMBER) return null;
                if (args_ary[2].type != ExprNodeType.STRING) return null;

                double m = skk_assoc_units (args_ary[0].data, args_ary[2].data);
                string res = ((double) args_ary[1].number * m).to_string ();
                return string_node (res + args_ary[2].data);
            }
            else if (func.data == "skk-current-date") {
                var dt = skk_current_date_1 ();

                if (iter.next ()) {
                    var lmd = iter.get ();
                    if (lmd.type != ExprNodeType.ARRAY) return null;
                    // ignore rest arguments

                    var params = new LinkedList<ExprNode?> ();
                    params.add (array_node (dt));
                    var sym_nil = symbol_node ("nil");
                    params.add (sym_nil);
                    params.add (sym_nil);
                    params.add (sym_nil);

                    return call_lambda (lmd, params, env);
                }
                else {
                    var rtn = skk_default_current_date (dt, null, 1, true, 0, 0, 0);
                    return string_node (rtn);
                }
            }
            else if (func.data == "skk-default-current-date") {
                ExprNode[] args_ary = args_to_array (7, iter);
                if (args_ary == null) return null;

                if (args_ary[0].type != ExprNodeType.ARRAY) return null;
                string? format = (args_ary[1].type == ExprNodeType.STRING ?
                                  args_ary[1].data : null);
                if (args_ary[2].type != ExprNodeType.NUMBER) return null;
                bool gengo_p = !(args_ary[3].type == ExprNodeType.SYMBOL &&
                                 args_ary[3].data == "nil");
                if (args_ary[4].type != ExprNodeType.NUMBER) return null;
                int month_index = (args_ary[5].type == ExprNodeType.NUMBER ?
                                   args_ary[5].number : -1);
                int dow_index = (args_ary[6].type == ExprNodeType.NUMBER ?
                                 args_ary[6].number : -1);

                var rtn = skk_default_current_date (args_ary[0].nodes, format, args_ary[2].number, gengo_p, args_ary[4].number, month_index, dow_index);
                return string_node (rtn);
            }
            else if (func.data == "skk-ad-to-gengo") {
                ExprNode[] args_ary = args_to_array (3, iter);
                if (args_ary == null) return null;
                if (args_ary[0].type != ExprNodeType.NUMBER) return null;

                var iter2 = env.get ("skk-num-list").nodes.list_iterator ();
                if (!iter2.next ()) return null;
                int ad = int.parse (iter2.get ().data);

                var builder = new StringBuilder ();
                var g = skk_ad_to_gengo_1 (ad);
                if (g == null) return null;
                builder.append (g.strs[args_ary[0].number]);
                if (args_ary[1].type == ExprNodeType.STRING) {
                    builder.append (args_ary[1].data);
                }
                builder.append (g.num.to_string ());
                if (args_ary[2].type == ExprNodeType.STRING) {
                    builder.append (args_ary[2].data);
                }
                return string_node (builder.str);
            }
            else if (func.data == "skk-gengo-to-ad") {
                ExprNode[] args_ary = args_to_array (2, iter);
                if (args_ary == null) return null;

                var iter2 = env.get ("skk-num-list").nodes.list_iterator ();
                if (!iter2.next ()) return null;
                int y = int.parse (iter2.get ().data);

                string midasi = env.get ("skk-henkan-key").data;

                int idx = midasi.index_of ("#");
                if (idx <= 0) return null;
                string gengo_hira = midasi.substring (0, idx);

                var builder = new StringBuilder ();
                int ad = skk_gengo_to_ad_1 (gengo_hira, y);
                if (ad < 0) return null;
                if (args_ary[0].type == ExprNodeType.STRING) {
                    builder.append (args_ary[0].data);
                }
                builder.append (ad.to_string ());
                if (args_ary[1].type == ExprNodeType.STRING) {
                    builder.append (args_ary[1].data);
                }
                return string_node (builder.str);
            }
            return null;
        }

        private ExprNode? _eval (ExprNode node, Map<string, ExprNode?> env) {
            if (node.type == ExprNodeType.ARRAY) {
                var iter = node.nodes.list_iterator ();
                if (iter.first ()) {
                    var func = iter.get ();
                    if (func.type == ExprNodeType.SYMBOL) {
                        if (func.data == "lambda") {
                            return node;
                        }
                        var args = new LinkedList<ExprNode?> ();
                        while (iter.next ()) {
                            var rtn = _eval (iter.get (), env);
                            if (rtn == null) return null;
                            args.add (rtn);
                        }
                        return apply (func, args, env);
                    }
                }
                return null;
            }
            else if (node.type == ExprNodeType.SYMBOL) {
                if (node.data.get_char (0) == '\'' ||
                    node.data == "nil") {
                    return node;
                }
                else if (env.has_key (node.data)) {
                    return env.get (node.data);
                }
            }
            else if (node.type == ExprNodeType.STRING ||
                     node.type == ExprNodeType.NUMBER) {
                return node;
            }
            return null;
        }

        public string? eval (ExprNode node, int[] numerics, string midasi) {
            Map<string, ExprNode?> env = new HashMap<string, ExprNode?> ();
            var num_list = new LinkedList<ExprNode?> ();
            for (int i = 0; i < numerics.length; i++) {
                num_list.add (string_node (numerics[i].to_string ()));
            }
            env.set ("skk-num-list", array_node (num_list));
            env.set ("skk-henkan-key", string_node (midasi));
            env.set ("fill-column", number_node (70));

            ExprNode? rtn = _eval (node, env);
            if (rtn != null) {
                if (rtn.type == ExprNodeType.STRING) {
                    return rtn.data;
                }
                else if (rtn.type == ExprNodeType.NUMBER) {
                    return rtn.number.to_string ();
                }
            }
            return null;
        }
    }
}
