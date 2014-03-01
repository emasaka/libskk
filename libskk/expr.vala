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
    errordomain LispError { TYPE, VAR, FUNC, PARAM, UNKNOWN }

    interface LispObject : Object {
        public abstract string to_string ();
    }

    class LispString : Object, LispObject {
        public string data { get; private set; }
        public LispString (string data) { this.data = data; }

        public string to_string () { return this.data; }
    }

    class LispInt : Object, LispObject {
        public int data { get; private set; }
        public LispInt (int data) { this.data = data; }

        public string to_string () { return this.data.to_string (); }
    }

    class LispSymbol : Object, LispObject {
        public string data { get; private set; }
        public LispSymbol (string data) { this.data = data; }

        public string to_string () { return this.data; }
    }

    interface LispList : LispObject {
        public abstract LispList rcons (LispObject x);
    }

    class LispNil : Object, LispObject, LispList {
        private static LispNil instance;

        public static LispNil get () {
            if (instance == null) {
                instance = new LispNil ();
            }
            return instance;
        }

        public LispList rcons (LispObject x) {
            return new LispCons (x, this);
        }

        public string to_string () { return ""; }
    }

    class LispCons : Object, LispObject, LispList {
        public LispObject car { get; set; }
        public LispObject cdr { get; set; }

        public LispCons (LispObject kar, LispObject kdr) {
            this.car = kar;
            this.cdr = kdr;
        }

        public LispList rcons (LispObject x) {
            LispCons p = this;
            while (p.cdr is LispCons) {
                p = (LispCons) p.cdr;
            }
            var old = p.cdr;
            p.cdr = new LispCons (x, old);
            return this;
        }

        public LispObject nth (int n) throws LispError {
            LispObject p = this;
            for (int i = 0; i < n; i++) {
                if (! (p is LispCons)) throw new LispError.PARAM ("");
                p = ((LispCons) p).cdr;
            }
            return ((LispCons) p).car;
        }

        public string to_string () { return ""; }
    }

    class ExprReader : Object {
        public LispObject read_symbol (string expr, ref int index) {
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
            if (builder.str == "nil") {
                return LispNil.get ();
            }
            return new LispSymbol (builder.str);
        }

        public LispString read_string (string expr, ref int index) {
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
            return new LispString (builder.str);
        }

        public LispInt read_number (string expr, ref int index) {
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
            return new LispInt (n);
        }

        public LispInt read_character (string expr, ref int index) {
            unichar uc = '\0';
            // TODO: handle escaped characters
            expr.get_next_char (ref index, out uc);
            return new LispInt ((int) uc);
        }

        public LispList read_list (string expr, ref int index) {
            LispList r = LispNil.get ();
            bool stop = false;
            index++;
            unichar uc = '\0';
            while (!stop && expr.get_next_char (ref index, out uc)) {
                switch (uc) {
                case ' ': case '\t': case '\n':
                    break;
                case ')':
                    stop = true;
                    break;
                default:
                    index--;
                    r = r.rcons (read_expr (expr, ref index));
                    break;
                }
            }
            return r;
        }

        public LispObject read_expr (string expr, ref int index) {
            unichar uc = '\0';
            while (expr.get_next_char (ref index, out uc)) {
                switch (uc) {
                case ' ': case '\t': case '\n':
                    break;
                case '(':
                    index--;
                    return read_list (expr, ref index);
                case '"':
                    index--;
                    return read_string (expr, ref index);
                case '0': case '1': case '2': case '3': case '4':
                case '5': case '6': case '7': case '8': case '9':
                    index--;
                    return read_number (expr, ref index);
                case '?':
                    return read_character (expr, ref index);
                case '\'':
                    var x = read_expr (expr, ref index);
                    return new LispCons (new LispSymbol ("quote"),
                                         new LispCons (x, LispNil.get ()));
                default:
                    index--;
                    return read_symbol (expr, ref index);
                }
            }
            // empty expr string -> empty list
            return LispNil.get ();
        }
    }

    class Env {
        private Map<string, LispObject> vars;
        private Env next;

        public Env (Env? nxt) {
            this.vars = new HashMap<string, LispObject> ();
            this.next = nxt;
        }

        private Env? find_frame (string key) {
            Env? p = this;
            do {
                if (p.vars.has_key (key)) return p;
                p = p.next;
            } while (p != null);
            return null;
        }

        public LispObject? get_var (string key) {
            Env? p = find_frame (key);
            if (p == null) return null;
            return p.vars.get (key);
        }

        public void set_var1 (string key, LispObject val) {
            this.vars.set (key, val);
        }
    }

    delegate LispObject LispFuncPtr (LispList args, Env env);

    // wrap delegates to store in HashMap
    struct LispFunc {
        public LispFuncPtr func;
        public LispFunc (LispFuncPtr f) { func = f; }
    }

    class ExprEvaluator : Object {
        private Map<string, LispFunc?> funcs = new HashMap<string, LispFunc?> ();

        public LispObject f_concat (LispList args, Env env) {
            LispObject p = args;
            var builder = new StringBuilder ();
            while (p is LispCons) {
                var e = ((LispCons) p).car;
                if (e is LispString) {
                    builder.append (((LispString) e).data);
                }
                p = ((LispCons) p).cdr;
            }
            return new LispString (builder.str);
        }

        public LispObject f_current_time_string (LispList args, Env env) {
            var d = asctime_array (new DateTime.now_local ());
            string asc = "%s %s %2s %s:%s:%s %s".printf(d[3], d[1], d[2], d[4],
                                                        d[5], d[6], d[0]);
            return new LispString (asc);
        }

        public LispObject f_pwd (LispList args, Env env) {
            return new LispString (Environment.get_current_dir ());
        }

        public LispObject f_skk_version (LispList args, Env env) {
            return new LispString ("%s/%s".printf (Config.PACKAGE_NAME,
                                                   Config.PACKAGE_VERSION));
        }

        public LispObject f_minus (LispList args, Env env) {
            return new LispInt (((LispInt) ((LispCons) args).nth (0)).data -
                                ((LispInt) ((LispCons) args).nth (1)).data);
        }

        public LispObject f_make_string (LispList args, Env env) {
            var builder = new StringBuilder ();
            int num = ((LispInt) ((LispCons) args).nth (0)).data;
            unichar c = (unichar) ((LispInt) ((LispCons) args).nth (1)).data;
            for (int i = 0; i < num; i++) {
                builder.append_unichar (c);
            }
            return new LispString (builder.str);
        }

        public LispObject f_substring (LispList args, Env env) {
            int offset = ((LispInt) ((LispCons) args).nth (1)).data;
            int len = ((LispInt) ((LispCons) args).nth (2)).data - offset;
            string text = ((LispString) ((LispCons) args).nth (0)).data;
            return new LispString (text.substring (offset, len));
        }

        public LispObject f_car (LispList args, Env env) {
            return ((LispCons) ((LispCons) args).car).car;
        }

        public LispObject f_string_to_number (LispList args, Env env) {
            var e1 = ((LispCons) args).car;
            return new LispInt (int.parse (((LispString) e1).data));
        }

        public LispObject f_skk_times (LispList args, Env env) {
            var num_list = (LispList) env.get_var ("skk-num-list");
            LispObject p = num_list;
            int n = 1;
            while (p is LispCons) {
                var e = ((LispCons) p).car;
                if (e is LispString) {
                    n *= int.parse (((LispString) e).data);
                }
                p = ((LispCons) p).cdr;
            }
            return new LispString (n.to_string ());
        }

        private LispObject? assoc_s (string key, LispList lst) {
            LispObject p = lst;
            while (p is LispCons) {
                LispCons e = (LispCons) ((LispCons) p).car;
                if (((LispString) e.car).data == key) {
                    return ((LispCons) e.cdr).car;
                }
                p = ((LispCons) p).cdr;
            }
            return null;
        }

        private double skk_assoc_units (string u_from, string u_to) {
            const string alist_str = "
((\"mile\" ((\"km\" \"1.6093\") (\"yard\" \"1760\")))
 (\"yard\" ((\"feet\" \"3\") (\"cm\" \"91.44\")))
 (\"feet\" ((\"inch\" \"12\") (\"cm\" \"30.48\")))
 (\"inch\" ((\"feet\" \"0.5\") (\"cm\" \"2.54\"))))";

            var reader = new ExprReader ();
            int index = 0;
            var alist = reader.read_expr (alist_str, ref index);
            var r1 = assoc_s (u_from, (LispList) alist);
            if (r1 == null) return 0;
            var r2 = assoc_s (u_to, (LispList) r1);
            if (r2 == null) return 0;
            return double.parse (((LispString) r2).data);
        }

        public LispObject f_skk_gadget_units_conversion (LispList args, Env env) {
            string u_from = ((LispString) ((LispCons) args).nth (0)).data;
            string u_to = ((LispString) ((LispCons) args).nth (2)).data;
            int x = ((LispInt) ((LispCons) args).nth (1)).data;
            double m = skk_assoc_units (u_from, u_to);
            string res = ((double) x * m).to_string ();
            return new LispString (res + u_to);
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

        public LispObject f_skk_ad_to_gengo (LispList args, Env env) {
            var num_list = (LispList) env.get_var ("skk-num-list");
            int ad = int.parse (((LispString) ((LispCons) num_list).car).data);

            var builder = new StringBuilder ();
            var g = skk_ad_to_gengo_1 (ad);
            if (g == null) return LispNil.get ();
            builder.append (g.strs[((LispInt) ((LispCons) args).nth (0)).data]);
            var mae = ((LispCons) args).nth (1);
            if (mae is LispString) {
                builder.append (((LispString) mae).data);
            }
            builder.append (g.num.to_string ());
            var ato = ((LispCons) args).nth (2);
            if (ato is LispString) {
                builder.append (((LispString) ato).data);
            }
            return new LispString (builder.str);
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

        public LispObject f_skk_gengo_to_ad (LispList args, Env env) {
            var num_list = (LispList) env.get_var ("skk-num-list");
            int y = int.parse (((LispString) ((LispCons) num_list).car).data);
            string midasi = ((LispString) env.get_var ("skk-henkan-key")).data;

            int idx = midasi.index_of ("#");
            string gengo_hira = midasi.substring (0, idx);
            var builder = new StringBuilder ();
            int ad = skk_gengo_to_ad_1 (gengo_hira, y);
            var mae = ((LispCons) args).nth (0);
            if (mae is LispString) {
                builder.append (((LispString) mae).data);
            }
            builder.append (ad.to_string ());
            var ato = ((LispCons) args).nth (1);
            if (ato is LispString) {
                builder.append (((LispString) ato).data);
            }
            return new LispString (builder.str);
        }

        const string[] MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
        const string[] DOWS_EN = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
        const string[] DOWS_JA = {"月", "火", "水", "木", "金", "土", "日"};

        private int skk_assoc_month (string month) {
            for (var i = 0; i < 12; i++) {
                if (month == MONTHS[i]) {
                    return i + 1;
                }
            }
            return -1;
        }

        private string? skk_assoc_dow (string dow) {
            for (var i = 0; i < 7; i++) {
                if (dow == DOWS_EN[i]) {
                    return DOWS_JA[i];
                }
            }
            return null;
        }

        private string[] asctime_array (DateTime dt) {
            return {dt.get_year ().to_string (),
                    MONTHS[dt.get_month () - 1],
                    dt.get_day_of_month ().to_string (),
                    DOWS_EN[dt.get_day_of_week () - 1],
                    "%02d".printf(dt.get_hour ()),
                    "%02d".printf(dt.get_minute ()),
                    "%02d".printf(dt.get_second ())};
        }

        private LispCons skk_current_date_1 () {
            string[] dt_a = asctime_array (new DateTime.now_local ());
            LispList dt_l = LispNil.get ();
            foreach (var x in dt_a) {
                dt_l = dt_l.rcons (new LispString (x));
            }
            return (LispCons) dt_l;
        }

        private string? skk_default_current_date (LispList date_info,
                                                 string? format, int num_type,
                                                 bool gengo_p, int gengo_index,
                                                 int month_index, int dow_index) {
            var d_year = ((LispCons) date_info).nth(0);
            var d_month = ((LispCons) date_info).nth(1);
            var d_day = ((LispCons) date_info).nth(2);
            var d_dow = ((LispCons) date_info).nth(3);
            // ignore rest arguments

            string? year_str = null;
            int year_i = int.parse (((LispString) d_year).data);
            if (gengo_p) {
                var g = skk_ad_to_gengo_1 (year_i);
                year_str = g.strs [gengo_index] +
                    Util.get_numeric (g.num, (NumericConversionType) num_type);
            }
            else {
                year_str = Util.get_numeric (year_i,
                                             (NumericConversionType) num_type);
            }

            string month_str = ((LispString) d_month).data;
            if (month_index >= 0) {
                int month_i = skk_assoc_month (((LispString) d_month).data);
                if (month_i < 0) return null;
                month_str = Util.get_numeric (month_i,
                                              (NumericConversionType) num_type);
            }

            string day_str = Util.get_numeric (int.parse (((LispString) d_day).data),
                                               (NumericConversionType) num_type);

            string dow_str = ((LispString) d_dow).data;
            if (dow_index >= 0) {
                var dow2 = skk_assoc_dow (((LispString) d_dow).data);
                if (dow2 == null) return null;
                dow_str = dow2;
            }

            string fmt = ((format == null) ? "%s年%s月%s日(%s)" : format);
            return fmt.printf (year_str, month_str, day_str, dow_str);
        }

        public LispObject f_skk_current_date (LispList args, Env env) {
            var dt = skk_current_date_1 ();

            if (args is LispCons) {
                var lmd = ((LispCons) args).car;
                // ignore rest arguments

                LispList params = LispNil.get ();
                params = params.rcons (dt);
                params.rcons (LispNil.get ());
                params.rcons (LispNil.get ());
                params.rcons (LispNil.get ());
                return apply_lambda ((LispList) lmd, params, env);
            }
            else {
                var rtn = skk_default_current_date (dt, null, 1, true, 0, 0, 0);
                return new LispString (rtn);
            }
        }

        public LispObject f_skk_default_current_date (LispList args, Env env) {
            var dt = ((LispCons) args).nth(0);
            var fmt = ((LispCons) args).nth(1);
            var num_type = ((LispCons) args).nth(2);
            var gengo = ((LispCons) args).nth(3);
            var gengo_index = ((LispCons) args).nth(4);
            var month_index = ((LispCons) args).nth(5);
            var dow_index = ((LispCons) args).nth(6);

            var rtn = skk_default_current_date (
                (LispList) dt,
                ((fmt is LispString) ? ((LispString) fmt).data : null),
                ((LispInt) num_type).data,
                !(gengo is LispNil),
                ((LispInt) gengo_index).data,
                ((month_index is LispInt) ? ((LispInt) month_index).data : -1),
                ((dow_index is LispInt) ? ((LispInt) dow_index).data : -1));
            return new LispString (rtn);
        }

        public LispObject apply_lambda (LispList lmd, LispList args, Env env) throws LispError {
            var new_env = new Env (env);

            LispObject p = ((LispCons) lmd).cdr; // skip 'lambda'
            LispObject params_p = ((LispCons) p).car;
            LispObject args_p = args;
            while (params_p is LispCons) {
                if (!(args_p is LispCons)) throw new LispError.PARAM ("");
                new_env.set_var1 (((LispSymbol) ((LispCons) params_p).car).data,
                                  ((LispCons) args_p).car);
                args_p = ((LispCons) args_p).cdr;
                params_p = ((LispCons) params_p).cdr;
            }

            p = ((LispCons) p).cdr;
            LispObject rtn = LispNil.get ();
            while (p is LispCons) {
                rtn = eval (((LispCons) p).car, new_env);
                p = ((LispCons) p).cdr;
            }
            return rtn;
        }

        public LispObject apply (LispObject func, LispList args, Env env) throws LispError {
            if (func is LispSymbol) {
                string funcname = ((LispSymbol) func).data;
                if (funcs.has_key (funcname)) {
                    LispFunc f = funcs.get (funcname);
                    return f.func(args, env);
                }
                throw new LispError.FUNC ("");
            }
            throw new LispError.TYPE ("");
        }

        public LispObject eval (LispObject x, Env env) throws LispError {
            if (x is LispCons) {
                var e1 = ((LispCons) x).car;
                if (e1 is LispSymbol) {
                    if (((LispSymbol) e1).data == "lambda") {
                        return x;
                    }
                    else if (((LispSymbol) e1).data == "quote") {
                        return ((LispCons) ((LispCons) x).cdr).car;
                    }
                    LispList args = LispNil.get ();
                    LispObject p = ((LispCons) x).cdr;
                    while (p is LispCons) {
                        args = args.rcons (eval (((LispCons) p).car, env));
                        p = ((LispCons) p).cdr;
                    }
                    return apply (e1, args, env);
                }
                throw new LispError.TYPE ("");
            }
            else if (x is LispSymbol) {
                string name = ((LispSymbol) x).data;
                var rtn = env.get_var (name);
                if (rtn != null) {
                    return rtn;
                }
                throw new LispError.VAR ("");
            }
            else if (x is LispString || x is LispInt || x is LispNil) {
                return x;
            }
            // NOTREACHED
            throw new LispError.UNKNOWN ("");
        }

        public void init_funcs () {
            funcs.set ("concat", LispFunc (this.f_concat));
            funcs.set ("current-time-string",
                      LispFunc (this.f_current_time_string));
            funcs.set ("pwd", LispFunc (this.f_pwd));
            funcs.set ("skk-version", LispFunc (this.f_skk_version));
            funcs.set ("-", LispFunc (this.f_minus));
            funcs.set ("make-string", LispFunc (this.f_make_string));
            funcs.set ("substring", LispFunc (this.f_substring));
            funcs.set ("car", LispFunc (this.f_car));
            funcs.set ("string-to-number", LispFunc (this.f_string_to_number));
            funcs.set ("skk-times", LispFunc (this.f_skk_times));
            funcs.set ("skk-gadget-units-conversion",
                       LispFunc (this.f_skk_gadget_units_conversion));
            funcs.set ("skk-ad-to-gengo", LispFunc (this.f_skk_ad_to_gengo));
            funcs.set ("skk-gengo-to-ad", LispFunc (this.f_skk_gengo_to_ad));
            funcs.set ("skk-current-date", LispFunc (this.f_skk_current_date));
            funcs.set ("skk-default-current-date",
                       LispFunc (this.f_skk_default_current_date));
        }

        public string? eval_expr (LispObject x, int[] numerics, string midasi) {
            Env env = new Env (null);
            LispList lst = LispNil.get ();
            for (int i = 0; i < numerics.length; i++) {
                lst = lst.rcons (new LispString (numerics[i].to_string()));
            }
            env.set_var1 ("skk-num-list", lst);
            env.set_var1 ("skk-henkan-key", new LispString (midasi));
            env.set_var1 ("fill-column", new LispInt (70));
            init_funcs ();

            LispObject? rtn = null;
            try {
                rtn = eval (x, env);
            } catch (LispError e) {
                return null;
            }
            return rtn.to_string ();
        }
    }
}
