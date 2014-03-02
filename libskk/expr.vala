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
        public virtual LispObject eval (Env env, ExprEvaluator ev) throws LispError {
            return this;
        }
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

        public LispObject eval (Env env, ExprEvaluator ev) throws LispError {
            string name = this.data;
            var rtn = env.get_var (name);
            if (rtn != null) {
                return rtn;
            }
            throw new LispError.VAR ("");
        }

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

        public LispObject eval (Env env, ExprEvaluator ev) throws LispError {
            var e1 = this.car;
            if (e1 is LispSymbol) {
                if (((LispSymbol) e1).data == "lambda") {
                    return this;
                }
                else if (((LispSymbol) e1).data == "quote") {
                    return ((LispCons) this.cdr).car;
                }
                LispObject[] args = {};
                LispObject p = this.cdr;
                while (p is LispCons) {
                    args += (((LispCons) p).car).eval (env, ev);
                    p = ((LispCons) p).cdr;
                }
                return ev.apply (e1, args, env);
            }
            throw new LispError.TYPE ("");
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

    delegate LispObject LispFuncPtr (LispObject[] args, Env env) throws LispError;

    // wrap delegates to store in HashMap
    struct LispFunc {
        public LispFuncPtr func;
        public LispFunc (LispFuncPtr f) { func = f; }
    }

    class ExprEvaluator : Object {
        private Map<string, LispFunc?> funcs = new HashMap<string, LispFunc?> ();

        public LispObject f_concat (LispObject[] args, Env env) throws LispError {
            var builder = new StringBuilder ();
            foreach (var e in args) {
                if (e is LispString) {
                    builder.append (((LispString) e).data);
                }
            }
            return new LispString (builder.str);
        }

        public LispObject f_current_time_string (LispObject[] args, Env env) throws LispError {
            var d = asctime_array (new DateTime.now_local ());
            string asc = "%s %s %2s %s:%s:%s %s".printf(d[3], d[1], d[2], d[4],
                                                        d[5], d[6], d[0]);
            return new LispString (asc);
        }

        public LispObject f_pwd (LispObject[] args, Env env) throws LispError {
            return new LispString (Environment.get_current_dir ());
        }

        public LispObject f_skk_version (LispObject[] args, Env env) throws LispError {
            return new LispString ("%s/%s".printf (Config.PACKAGE_NAME,
                                                   Config.PACKAGE_VERSION));
        }

        public LispObject f_minus (LispObject[] args, Env env) throws LispError {
            if (args.length != 2) throw new LispError.PARAM ("");
            return new LispInt (((LispInt) args[0]).data -
                                ((LispInt) args[1]).data);
        }

        public LispObject f_make_string (LispObject[] args, Env env) throws LispError {
            if (args.length != 2) throw new LispError.PARAM ("");
            var builder = new StringBuilder ();
            int num = ((LispInt) args[0]).data;
            unichar c = (unichar) ((LispInt) args[1]).data;
            for (int i = 0; i < num; i++) {
                builder.append_unichar (c);
            }
            return new LispString (builder.str);
        }

        public LispObject f_substring (LispObject[] args, Env env) throws LispError {
            if (args.length != 3) throw new LispError.PARAM ("");
            int offset = ((LispInt) args[1]).data;
            int len = ((LispInt) args[2]).data - offset;
            string text = ((LispString) args[0]).data;
            return new LispString (text.substring (offset, len));
        }

        public LispObject f_car (LispObject[] args, Env env) throws LispError {
            if (args.length != 1) throw new LispError.PARAM ("");
            return ((LispCons) args[0]).car;
        }

        public LispObject f_string_to_number (LispObject[] args, Env env) throws LispError {
            if (args.length != 1) throw new LispError.PARAM ("");
            return new LispInt (int.parse (((LispString) args[0]).data));
        }

        public LispObject f_skk_times (LispObject[] args, Env env) throws LispError {
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

        public LispObject f_skk_gadget_units_conversion (LispObject[] args, Env env) throws LispError {
            if (args.length != 3) throw new LispError.PARAM ("");
            string u_from = ((LispString) args[0]).data;
            string u_to = ((LispString) args[2]).data;
            int x = ((LispInt) args[1]).data;
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

        public LispObject f_skk_ad_to_gengo (LispObject[] args, Env env) throws LispError {
            if (args.length != 3) throw new LispError.PARAM ("");
            var num_list = (LispList) env.get_var ("skk-num-list");
            int ad = int.parse (((LispString) ((LispCons) num_list).car).data);

            var builder = new StringBuilder ();
            var g = skk_ad_to_gengo_1 (ad);
            if (g == null) return LispNil.get ();
            builder.append (g.strs[((LispInt) args[0]).data]);
            if (args[1] is LispString) {
                builder.append (((LispString) args[1]).data);
            }
            builder.append (g.num.to_string ());
            if (args[2] is LispString) {
                builder.append (((LispString) args[2]).data);
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

        public LispObject f_skk_gengo_to_ad (LispObject[] args, Env env) throws LispError {
            if (args.length != 2) throw new LispError.PARAM ("");
            var num_list = (LispList) env.get_var ("skk-num-list");
            int y = int.parse (((LispString) ((LispCons) num_list).car).data);
            string midasi = ((LispString) env.get_var ("skk-henkan-key")).data;

            int idx = midasi.index_of ("#");
            string gengo_hira = midasi.substring (0, idx);
            var builder = new StringBuilder ();
            int ad = skk_gengo_to_ad_1 (gengo_hira, y);
            if (args[0] is LispString) {
                builder.append (((LispString) args[0]).data);
            }
            builder.append (ad.to_string ());
            if (args[1] is LispString) {
                builder.append (((LispString) args[1]).data);
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

        public LispObject f_skk_current_date (LispObject[] args, Env env) throws LispError {
            var dt = skk_current_date_1 ();

            if (args.length == 0) {
                var rtn = skk_default_current_date (dt, null, 1, true, 0, 0, 0);
                return new LispString (rtn);
            }
            else {
                // ignore arguments except for 1st argument
                LispObject[] params = {dt, LispNil.get (),
                                       LispNil.get (), LispNil.get ()};
                return apply_lambda ((LispList) args[0], params, env);
            }
        }

        public LispObject f_skk_default_current_date (LispObject[] args, Env env) throws LispError {
            if (args.length != 7) throw new LispError.PARAM ("");
            var dt = args[0];
            var fmt = args[1];
            var num_type = args[2];
            var gengo = args[3];
            var gengo_index = args[4];
            var month_index = args[5];
            var dow_index = args[6];

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

        public LispObject apply_lambda (LispList lmd, LispObject[] args, Env env) throws LispError {
            var new_env = new Env (env);

            LispObject p = ((LispCons) lmd).cdr; // skip 'lambda'
            LispObject params_p = ((LispCons) p).car;
            foreach (var arg in args) {
                new_env.set_var1 (((LispSymbol) ((LispCons) params_p).car).data,
                                  arg);
                params_p = ((LispCons) params_p).cdr;
            }

            p = ((LispCons) p).cdr;
            LispObject rtn = LispNil.get ();
            while (p is LispCons) {
                rtn = (((LispCons) p).car).eval (new_env, this);
                p = ((LispCons) p).cdr;
            }
            return rtn;
        }

        public LispObject apply (LispObject func, LispObject[] args, Env env) throws LispError {
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
                rtn = x.eval (env, this);
            } catch (LispError e) {
                return null;
            }
            return rtn.to_string ();
        }
    }
}
