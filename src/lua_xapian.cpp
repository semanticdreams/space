#include <sol/sol.hpp>

#include <memory>
#include <string>
#include <vector>

#include <xapian.h>

namespace {

struct XapianDb {
    explicit XapianDb(std::unique_ptr<Xapian::Database> db_ref)
        : db(std::move(db_ref))
    {
    }

    explicit XapianDb(std::unique_ptr<Xapian::WritableDatabase> db_ref)
        : writable(std::move(db_ref))
    {
    }

    bool is_closed() const { return closed; }
    bool is_writable() const { return writable != nullptr; }

    void close()
    {
        if (!closed) {
            db.reset();
            writable.reset();
            closed = true;
        }
    }

    Xapian::Database& read()
    {
        ensure_open("read");
        if (writable) {
            return *writable;
        }
        return *db;
    }

    Xapian::WritableDatabase& write()
    {
        ensure_open("write");
        if (!writable) {
            throw sol::error("xapian database is read-only: write");
        }
        return *writable;
    }

private:
    void ensure_open(const std::string& action) const
    {
        if (closed) {
            throw sol::error("xapian database is closed: " + action);
        }
    }

    std::unique_ptr<Xapian::Database> db;
    std::unique_ptr<Xapian::WritableDatabase> writable;
    bool closed { false };
};

template <typename Fn>
auto xapian_call(const char* label, Fn&& fn) -> decltype(fn())
{
    try {
        return fn();
    } catch (const Xapian::Error& err) {
        throw sol::error(std::string("xapian ") + label + ": " + err.get_description());
    }
}

Xapian::Document build_document(const sol::optional<sol::table>& opts_opt)
{
    Xapian::Document doc;
    if (!opts_opt) {
        return doc;
    }

    sol::table opts = *opts_opt;
    sol::optional<std::string> data_opt = opts.get<sol::optional<std::string>>("data");
    sol::optional<std::string> text_opt = opts.get<sol::optional<std::string>>("text");
    sol::optional<std::string> stemmer_opt = opts.get<sol::optional<std::string>>("stemmer");
    sol::optional<sol::table> terms_opt = opts.get<sol::optional<sol::table>>("terms");
    sol::optional<sol::table> values_opt = opts.get<sol::optional<sol::table>>("values");

    if (data_opt) {
        doc.set_data(*data_opt);
    }

    if (text_opt) {
        Xapian::TermGenerator termgen;
        termgen.set_document(doc);
        if (stemmer_opt) {
            termgen.set_stemmer(Xapian::Stem(*stemmer_opt));
        }
        termgen.index_text(*text_opt);
    }

    if (terms_opt) {
        sol::table terms = *terms_opt;
        for (auto& kv : terms) {
            sol::object term_obj = kv.second;
            if (!term_obj.is<std::string>()) {
                throw sol::error("xapian.document terms must be strings");
            }
            doc.add_term(term_obj.as<std::string>());
        }
    }

    if (values_opt) {
        sol::table values = *values_opt;
        for (auto& kv : values) {
            sol::object key_obj = kv.first;
            sol::object value_obj = kv.second;
            if (!key_obj.is<int>() && !key_obj.is<int64_t>()) {
                throw sol::error("xapian.document values keys must be integers");
            }
            if (!value_obj.is<std::string>()) {
                throw sol::error("xapian.document values must be strings");
            }
            int64_t index = key_obj.as<int64_t>();
            if (index < 0) {
                throw sol::error("xapian.document values keys must be non-negative");
            }
            doc.add_value(static_cast<Xapian::valueno>(index), value_obj.as<std::string>());
        }
    }

    return doc;
}

sol::table document_to_table(sol::state_view lua, const Xapian::Document& doc)
{
    sol::table out = lua.create_table();
    out["data"] = doc.get_data();

    sol::table values = lua.create_table();
    for (auto it = doc.values_begin(); it != doc.values_end(); ++it) {
        values[it.get_valueno()] = std::string(*it);
    }
    out["values"] = values;
    return out;
}

Xapian::Query::op parse_default_op(const sol::optional<std::string>& op_opt)
{
    if (!op_opt) {
        return Xapian::Query::OP_AND;
    }
    const std::string op = *op_opt;
    if (op == "and") {
        return Xapian::Query::OP_AND;
    }
    if (op == "or") {
        return Xapian::Query::OP_OR;
    }
    throw sol::error("xapian.search default-op must be 'and' or 'or'");
}

unsigned parse_query_flags(const sol::optional<sol::object>& flags_opt)
{
    if (!flags_opt || !flags_opt->valid() || flags_opt->is<sol::lua_nil_t>()) {
        return Xapian::QueryParser::FLAG_DEFAULT;
    }
    const sol::object& obj = *flags_opt;
    if (obj.is<int>()) {
        int value = obj.as<int>();
        if (value < 0) {
            throw sol::error("xapian.search flags must be non-negative");
        }
        return static_cast<unsigned>(value);
    }
    if (obj.is<int64_t>()) {
        int64_t value = obj.as<int64_t>();
        if (value < 0) {
            throw sol::error("xapian.search flags must be non-negative");
        }
        return static_cast<unsigned>(value);
    }
    if (!obj.is<sol::table>()) {
        throw sol::error("xapian.search flags must be an integer or list of strings");
    }

    sol::table flags = obj.as<sol::table>();
    unsigned out = 0;
    std::size_t len = flags.size();
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = flags.get<sol::object>(i);
        if (!item.is<std::string>()) {
            throw sol::error("xapian.search flags entries must be strings");
        }
        std::string name = item.as<std::string>();
        if (name == "boolean") {
            out |= Xapian::QueryParser::FLAG_BOOLEAN;
        } else if (name == "phrase") {
            out |= Xapian::QueryParser::FLAG_PHRASE;
        } else if (name == "lovehate") {
            out |= Xapian::QueryParser::FLAG_LOVEHATE;
        } else if (name == "boolean-any-case") {
            out |= Xapian::QueryParser::FLAG_BOOLEAN_ANY_CASE;
        } else if (name == "wildcard") {
            out |= Xapian::QueryParser::FLAG_WILDCARD;
        } else if (name == "pure-not") {
            out |= Xapian::QueryParser::FLAG_PURE_NOT;
        } else if (name == "partial") {
            out |= Xapian::QueryParser::FLAG_PARTIAL;
        } else if (name == "spelling-correction") {
            out |= Xapian::QueryParser::FLAG_SPELLING_CORRECTION;
        } else if (name == "synonym") {
            out |= Xapian::QueryParser::FLAG_SYNONYM;
        } else if (name == "auto-synonyms") {
            out |= Xapian::QueryParser::FLAG_AUTO_SYNONYMS;
        } else if (name == "auto-multiword-synonyms") {
            out |= Xapian::QueryParser::FLAG_AUTO_MULTIWORD_SYNONYMS;
        } else if (name == "cjk-ngram") {
            out |= Xapian::QueryParser::FLAG_CJK_NGRAM;
        } else if (name == "accumulate") {
            out |= Xapian::QueryParser::FLAG_ACCUMULATE;
        } else if (name == "default") {
            out |= Xapian::QueryParser::FLAG_DEFAULT;
        } else {
            throw sol::error("xapian.search unknown flag: " + name);
        }
    }
    return out;
}

struct PrefixSpec {
    std::string field;
    std::string prefix;
};

std::vector<PrefixSpec> parse_prefix_list(const sol::optional<sol::table>& list_opt,
    const std::string& label)
{
    std::vector<PrefixSpec> specs;
    if (!list_opt) {
        return specs;
    }
    sol::table list = *list_opt;
    std::size_t len = list.size();
    specs.reserve(len);
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = list.get<sol::object>(i);
        if (!item.is<sol::table>()) {
            throw sol::error("xapian.search " + label + " entries must be tables");
        }
        sol::table spec = item.as<sol::table>();
        sol::optional<std::string> field = spec.get<sol::optional<std::string>>("field");
        sol::optional<std::string> prefix = spec.get<sol::optional<std::string>>("prefix");
        if (!field || field->empty()) {
            throw sol::error("xapian.search " + label + " entries require field");
        }
        if (!prefix || prefix->empty()) {
            throw sol::error("xapian.search " + label + " entries require prefix");
        }
        specs.push_back(PrefixSpec{*field, *prefix});
    }
    return specs;
}

struct BooleanFilter {
    std::string prefix;
    std::string value;
};

std::vector<BooleanFilter> parse_boolean_filters(const sol::optional<sol::table>& list_opt)
{
    std::vector<BooleanFilter> filters;
    if (!list_opt) {
        return filters;
    }
    sol::table list = *list_opt;
    std::size_t len = list.size();
    filters.reserve(len);
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = list.get<sol::object>(i);
        if (!item.is<sol::table>()) {
            throw sol::error("xapian.search boolean-filters entries must be tables");
        }
        sol::table spec = item.as<sol::table>();
        sol::optional<std::string> prefix = spec.get<sol::optional<std::string>>("prefix");
        sol::optional<std::string> value = spec.get<sol::optional<std::string>>("value");
        if (!prefix || prefix->empty()) {
            throw sol::error("xapian.search boolean-filters entries require prefix");
        }
        if (!value || value->empty()) {
            throw sol::error("xapian.search boolean-filters entries require value");
        }
        filters.push_back(BooleanFilter{*prefix, *value});
    }
    return filters;
}

struct ExpandOptions {
    std::vector<Xapian::docid> docids;
    Xapian::termcount limit;
    int flags;
    double min_weight;
};

int parse_expand_flags(const sol::optional<sol::object>& flags_opt)
{
    if (!flags_opt || !flags_opt->valid() || flags_opt->is<sol::lua_nil_t>()) {
        return 0;
    }
    const sol::object& obj = *flags_opt;
    if (obj.is<int>()) {
        return obj.as<int>();
    }
    if (obj.is<int64_t>()) {
        return static_cast<int>(obj.as<int64_t>());
    }
    if (!obj.is<sol::table>()) {
        throw sol::error("xapian.search expand flags must be an integer or list of strings");
    }
    int out = 0;
    sol::table flags = obj.as<sol::table>();
    std::size_t len = flags.size();
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = flags.get<sol::object>(i);
        if (!item.is<std::string>()) {
            throw sol::error("xapian.search expand flags entries must be strings");
        }
        std::string name = item.as<std::string>();
        if (name == "include-query-terms") {
            out |= Xapian::Enquire::INCLUDE_QUERY_TERMS;
        } else if (name == "exact-termfreq") {
            out |= Xapian::Enquire::USE_EXACT_TERMFREQ;
        } else {
            throw sol::error("xapian.search expand unknown flag: " + name);
        }
    }
    return out;
}

unsigned parse_range_flags(const sol::optional<sol::table>& opts_opt)
{
    if (!opts_opt) {
        return 0;
    }
    sol::table opts = *opts_opt;
    unsigned flags = 0;
    if (opts.get_or("suffix", false)) {
        flags |= Xapian::RP_SUFFIX;
    }
    if (opts.get_or("repeated", false)) {
        flags |= Xapian::RP_REPEATED;
    }
    if (opts.get_or("prefer-mdy", false)) {
        flags |= Xapian::RP_DATE_PREFER_MDY;
    }
    return flags;
}

struct RangeSpec {
    std::string kind;
    Xapian::valueno slot;
    std::string prefix;
    unsigned flags;
    int epoch_year;
};

std::vector<RangeSpec> parse_range_processors(const sol::optional<sol::table>& list_opt)
{
    std::vector<RangeSpec> specs;
    if (!list_opt) {
        return specs;
    }
    sol::table list = *list_opt;
    std::size_t len = list.size();
    specs.reserve(len);
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = list.get<sol::object>(i);
        if (!item.is<sol::table>()) {
            throw sol::error("xapian.search ranges entries must be tables");
        }
        sol::table spec = item.as<sol::table>();
        sol::optional<std::string> kind = spec.get<sol::optional<std::string>>("type");
        sol::optional<int64_t> slot = spec.get<sol::optional<int64_t>>("slot");
        if (!kind || kind->empty()) {
            throw sol::error("xapian.search ranges entries require type");
        }
        if (!slot || *slot < 0) {
            throw sol::error("xapian.search ranges entries require non-negative slot");
        }
        sol::optional<std::string> prefix = spec.get<sol::optional<std::string>>("prefix");
        sol::optional<sol::table> opts = spec.get<sol::optional<sol::table>>("options");
        unsigned flags = parse_range_flags(opts);
        int epoch_year = spec.get_or("epoch-year", 1970);
        specs.push_back(RangeSpec{*kind, static_cast<Xapian::valueno>(*slot),
                                  prefix.value_or(std::string()), flags, epoch_year});
    }
    return specs;
}

Xapian::LMWeight::type_smoothing parse_lm_smoothing(const sol::optional<std::string>& name_opt)
{
    if (!name_opt) {
        return Xapian::LMWeight::TWO_STAGE_SMOOTHING;
    }
    const std::string& name = *name_opt;
    if (name == "two-stage") {
        return Xapian::LMWeight::TWO_STAGE_SMOOTHING;
    }
    if (name == "jelinek-mercer") {
        return Xapian::LMWeight::JELINEK_MERCER_SMOOTHING;
    }
    if (name == "dirichlet") {
        return Xapian::LMWeight::DIRICHLET_SMOOTHING;
    }
    if (name == "absolute") {
        return Xapian::LMWeight::ABSOLUTE_DISCOUNT_SMOOTHING;
    }
    if (name == "dirichlet-plus") {
        return Xapian::LMWeight::DIRICHLET_PLUS_SMOOTHING;
    }
    throw sol::error("xapian.search weighting unknown lm smoothing: " + name);
}

double param_or(const sol::optional<sol::table>& params, const char* key, int index, double fallback)
{
    if (params) {
        sol::table t = *params;
        sol::optional<double> value = t.get<sol::optional<double>>(key);
        if (value) {
            return *value;
        }
        sol::object item = t.get<sol::object>(index);
        if (item.is<double>()) {
            return item.as<double>();
        }
        if (item.is<int>()) {
            return static_cast<double>(item.as<int>());
        }
        if (item.is<int64_t>()) {
            return static_cast<double>(item.as<int64_t>());
        }
    }
    return fallback;
}

std::string param_string_or(const sol::optional<sol::table>& params, const char* key, int index,
    const std::string& fallback)
{
    if (params) {
        sol::table t = *params;
        sol::optional<std::string> value = t.get<sol::optional<std::string>>(key);
        if (value) {
            return *value;
        }
        sol::object item = t.get<sol::object>(index);
        if (item.is<std::string>()) {
            return item.as<std::string>();
        }
    }
    return fallback;
}

std::unique_ptr<Xapian::Weight> parse_weighting(const sol::optional<sol::object>& weight_opt)
{
    if (!weight_opt || !weight_opt->valid() || weight_opt->is<sol::lua_nil_t>()) {
        return nullptr;
    }
    std::string name;
    sol::optional<sol::table> params_opt;
    if (weight_opt->is<std::string>()) {
        name = weight_opt->as<std::string>();
    } else if (weight_opt->is<sol::table>()) {
        sol::table tbl = weight_opt->as<sol::table>();
        sol::optional<std::string> name_opt = tbl.get<sol::optional<std::string>>("name");
        if (!name_opt || name_opt->empty()) {
            throw sol::error("xapian.search weighting requires name");
        }
        name = *name_opt;
        params_opt = tbl.get<sol::optional<sol::table>>("params");
        if (!params_opt) {
            params_opt = tbl;
        }
    } else {
        throw sol::error("xapian.search weighting must be string or table");
    }

    if (name == "bm25") {
        double k1 = param_or(params_opt, "k1", 1, 1.0);
        double k2 = param_or(params_opt, "k2", 2, 0.0);
        double k3 = param_or(params_opt, "k3", 3, 1.0);
        double b = param_or(params_opt, "b", 4, 0.5);
        double min_normlen = param_or(params_opt, "min-normlen", 5, 0.5);
        return std::make_unique<Xapian::BM25Weight>(k1, k2, k3, b, min_normlen);
    }
    if (name == "bm25plus") {
        double k1 = param_or(params_opt, "k1", 1, 1.0);
        double k2 = param_or(params_opt, "k2", 2, 0.0);
        double k3 = param_or(params_opt, "k3", 3, 1.0);
        double b = param_or(params_opt, "b", 4, 0.5);
        double min_normlen = param_or(params_opt, "min-normlen", 5, 0.5);
        double delta = param_or(params_opt, "delta", 6, 1.0);
        return std::make_unique<Xapian::BM25PlusWeight>(k1, k2, k3, b, min_normlen, delta);
    }
    if (name == "trad") {
        double k = param_or(params_opt, "k", 1, 1.0);
        return std::make_unique<Xapian::TradWeight>(k);
    }
    if (name == "bool") {
        return std::make_unique<Xapian::BoolWeight>();
    }
    if (name == "coord") {
        return std::make_unique<Xapian::CoordWeight>();
    }
    if (name == "tfidf") {
        std::string norm = param_string_or(params_opt, "normalizations", 1, "ntn");
        return std::make_unique<Xapian::TfIdfWeight>(norm);
    }
    if (name == "inl2") {
        double c = param_or(params_opt, "c", 1, 1.0);
        return std::make_unique<Xapian::InL2Weight>(c);
    }
    if (name == "ifb2") {
        double c = param_or(params_opt, "c", 1, 1.0);
        return std::make_unique<Xapian::IfB2Weight>(c);
    }
    if (name == "ineb2") {
        double c = param_or(params_opt, "c", 1, 1.0);
        return std::make_unique<Xapian::IneB2Weight>(c);
    }
    if (name == "bb2") {
        double c = param_or(params_opt, "c", 1, 1.0);
        return std::make_unique<Xapian::BB2Weight>(c);
    }
    if (name == "dlh") {
        return std::make_unique<Xapian::DLHWeight>();
    }
    if (name == "pl2") {
        double c = param_or(params_opt, "c", 1, 1.0);
        return std::make_unique<Xapian::PL2Weight>(c);
    }
    if (name == "pl2plus") {
        return std::make_unique<Xapian::PL2PlusWeight>();
    }
    if (name == "dph") {
        return std::make_unique<Xapian::DPHWeight>();
    }
    if (name == "lm") {
        double log_value = param_or(params_opt, "log", 1, 0.0);
        double smoothing1 = param_or(params_opt, "smoothing1", 3, -1.0);
        double smoothing2 = param_or(params_opt, "smoothing2", 4, -1.0);
        sol::optional<std::string> smoothing_name;
        if (params_opt) {
            smoothing_name = params_opt->get<sol::optional<std::string>>("smoothing");
        }
        Xapian::LMWeight::type_smoothing smoothing = parse_lm_smoothing(smoothing_name);
        return std::make_unique<Xapian::LMWeight>(log_value, smoothing, smoothing1, smoothing2);
    }

    throw sol::error("xapian.search weighting unknown scheme: " + name);
}

std::vector<Xapian::docid> parse_docids(const sol::optional<sol::table>& list_opt, const std::string& label)
{
    std::vector<Xapian::docid> docids;
    if (!list_opt) {
        return docids;
    }
    sol::table list = *list_opt;
    std::size_t len = list.size();
    docids.reserve(len);
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = list.get<sol::object>(i);
        if (!item.is<int>() && !item.is<int64_t>()) {
            throw sol::error("xapian.search " + label + " docids must be integers");
        }
        int64_t value = item.as<int64_t>();
        if (value <= 0) {
            throw sol::error("xapian.search " + label + " docids must be positive");
        }
        docids.push_back(static_cast<Xapian::docid>(value));
    }
    return docids;
}

sol::optional<ExpandOptions> parse_expand_options(const sol::optional<sol::table>& expand_opt)
{
    if (!expand_opt) {
        return sol::nullopt;
    }
    sol::table expand = *expand_opt;
    sol::optional<sol::table> docids_opt = expand.get<sol::optional<sol::table>>("docids");
    if (!docids_opt) {
        throw sol::error("xapian.search expand requires docids");
    }
    std::vector<Xapian::docid> docids = parse_docids(docids_opt, "expand");
    int limit = expand.get_or("limit", 10);
    if (limit < 0) {
        throw sol::error("xapian.search expand limit must be non-negative");
    }
    int flags = parse_expand_flags(expand.get<sol::optional<sol::object>>("flags"));
    double min_weight = expand.get_or("min-weight", 0.0);
    if (min_weight < 0.0) {
        throw sol::error("xapian.search expand min-weight must be >= 0");
    }
    return ExpandOptions{std::move(docids), static_cast<Xapian::termcount>(limit), flags, min_weight};
}

struct ValueRangeFilter {
    Xapian::valueno slot;
    std::string start;
    std::string end;
};

std::vector<ValueRangeFilter> parse_value_ranges(const sol::optional<sol::table>& list_opt)
{
    std::vector<ValueRangeFilter> ranges;
    if (!list_opt) {
        return ranges;
    }
    sol::table list = *list_opt;
    std::size_t len = list.size();
    ranges.reserve(len);
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = list.get<sol::object>(i);
        if (!item.is<sol::table>()) {
            throw sol::error("xapian.search value-ranges entries must be tables");
        }
        sol::table spec = item.as<sol::table>();
        sol::optional<int64_t> slot = spec.get<sol::optional<int64_t>>("slot");
        sol::optional<std::string> start = spec.get<sol::optional<std::string>>("start");
        sol::optional<std::string> end = spec.get<sol::optional<std::string>>("end");
        if (!slot || *slot < 0) {
            throw sol::error("xapian.search value-ranges entries require non-negative slot");
        }
        if (!start) {
            throw sol::error("xapian.search value-ranges entries require start");
        }
        if (!end) {
            throw sol::error("xapian.search value-ranges entries require end");
        }
        ranges.push_back(ValueRangeFilter{static_cast<Xapian::valueno>(*slot), *start, *end});
    }
    return ranges;
}

struct SortSpec {
    Xapian::valueno slot;
    bool descending;
    bool then_relevance;
};

sol::optional<SortSpec> parse_sort_spec(const sol::optional<sol::table>& sort_opt)
{
    if (!sort_opt) {
        return sol::nullopt;
    }
    sol::table sort = *sort_opt;
    sol::optional<int64_t> slot = sort.get<sol::optional<int64_t>>("value");
    if (!slot || *slot < 0) {
        throw sol::error("xapian.search sort requires non-negative value slot");
    }
    bool descending = sort.get_or("descending", false);
    bool then_relevance = sort.get_or("then-relevance", false);
    return SortSpec{static_cast<Xapian::valueno>(*slot), descending, then_relevance};
}

struct CollapseSpec {
    Xapian::valueno slot;
    Xapian::doccount max;
};

sol::optional<CollapseSpec> parse_collapse_spec(const sol::optional<sol::table>& collapse_opt)
{
    if (!collapse_opt) {
        return sol::nullopt;
    }
    sol::table collapse = *collapse_opt;
    sol::optional<int64_t> slot = collapse.get<sol::optional<int64_t>>("value");
    if (!slot || *slot < 0) {
        throw sol::error("xapian.search collapse requires non-negative value slot");
    }
    int64_t max = collapse.get_or("max", 1);
    if (max < 1) {
        throw sol::error("xapian.search collapse max must be >= 1");
    }
    return CollapseSpec{static_cast<Xapian::valueno>(*slot), static_cast<Xapian::doccount>(max)};
}

sol::table create_xapian_table(sol::state_view lua)
{
    sol::table xapian = lua.create_table();

    xapian.new_usertype<Xapian::Document>("Document",
        sol::no_constructor,
        "data", sol::property(&Xapian::Document::get_data, &Xapian::Document::set_data),
        "add-term", &Xapian::Document::add_term,
        "add-value", [](Xapian::Document& self, Xapian::valueno slot, const std::string& value) {
            self.add_value(slot, value);
        }
    );

    xapian.new_usertype<XapianDb>("Database",
        sol::no_constructor,
        "close", &XapianDb::close,
        "is-closed", &XapianDb::is_closed,
        "is-writable", &XapianDb::is_writable,
        "doccount", [](XapianDb& self) {
            return xapian_call("doccount", [&]() { return self.read().get_doccount(); });
        },
        "commit", [](XapianDb& self) {
            xapian_call("commit", [&]() {
                self.write().commit();
                return 0;
            });
        },
        "add-document", [](XapianDb& self, const Xapian::Document& doc) {
            return xapian_call("add-document", [&]() { return self.write().add_document(doc); });
        },
        "replace-document", [](XapianDb& self, Xapian::docid id, const Xapian::Document& doc) {
            xapian_call("replace-document", [&]() {
                self.write().replace_document(id, doc);
                return 0;
            });
        },
        "delete-document", [](XapianDb& self, Xapian::docid id) {
            xapian_call("delete-document", [&]() {
                self.write().delete_document(id);
                return 0;
            });
        },
        "add-spelling", [](XapianDb& self, const std::string& word, sol::optional<int> freq_opt) {
            xapian_call("add-spelling", [&]() {
                self.write().add_spelling(word, static_cast<Xapian::termcount>(freq_opt.value_or(1)));
                return 0;
            });
        },
        "remove-spelling", [](XapianDb& self, const std::string& word, sol::optional<int> freq_opt) {
            xapian_call("remove-spelling", [&]() {
                self.write().remove_spelling(word, static_cast<Xapian::termcount>(freq_opt.value_or(1)));
                return 0;
            });
        },
        "spelling-suggestion", [](XapianDb& self, const std::string& word, sol::optional<int> max_edit_opt) {
            return xapian_call("spelling-suggestion", [&]() {
                return self.read().get_spelling_suggestion(word,
                    static_cast<unsigned>(max_edit_opt.value_or(2)));
            });
        },
        "termfreq", [](XapianDb& self, const std::string& term) {
            return xapian_call("termfreq", [&]() { return self.read().get_termfreq(term); });
        },
        "collection-freq", [](XapianDb& self, const std::string& term) {
            return xapian_call("collection-freq", [&]() { return self.read().get_collection_freq(term); });
        },
        "stats", [lua](XapianDb& self) {
            return xapian_call("stats", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                out["doccount"] = self.read().get_doccount();
                out["lastdocid"] = self.read().get_lastdocid();
                out["avg-length"] = self.read().get_avlength();
                out["total-length"] = self.read().get_total_length();
                out["doclength-min"] = self.read().get_doclength_lower_bound();
                out["doclength-max"] = self.read().get_doclength_upper_bound();
                return out;
            });
        },
        "doc-stats", [lua](XapianDb& self, Xapian::docid id) {
            return xapian_call("doc-stats", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                out["doclength"] = self.read().get_doclength(id);
                out["unique-terms"] = self.read().get_unique_terms(id);
                return out;
            });
        },
        "get-metadata", [](XapianDb& self, const std::string& key) {
            return xapian_call("get-metadata", [&]() { return self.read().get_metadata(key); });
        },
        "set-metadata", [](XapianDb& self, const std::string& key, const std::string& value) {
            xapian_call("set-metadata", [&]() {
                self.write().set_metadata(key, value);
                return 0;
            });
        },
        "metadata-keys", [lua](XapianDb& self, sol::optional<std::string> prefix_opt) {
            return xapian_call("metadata-keys", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                std::string prefix = prefix_opt.value_or(std::string());
                size_t index = 1;
                for (auto it = self.read().metadata_keys_begin(prefix);
                     it != self.read().metadata_keys_end(prefix); ++it, ++index) {
                    out[index] = std::string(*it);
                }
                return out;
            });
        },
        "add-synonym", [](XapianDb& self, const std::string& term, const std::string& synonym) {
            xapian_call("add-synonym", [&]() {
                self.write().add_synonym(term, synonym);
                return 0;
            });
        },
        "remove-synonym", [](XapianDb& self, const std::string& term, const std::string& synonym) {
            xapian_call("remove-synonym", [&]() {
                self.write().remove_synonym(term, synonym);
                return 0;
            });
        },
        "clear-synonyms", [](XapianDb& self, const std::string& term) {
            xapian_call("clear-synonyms", [&]() {
                self.write().clear_synonyms(term);
                return 0;
            });
        },
        "synonyms", [lua](XapianDb& self, const std::string& term) {
            return xapian_call("synonyms", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                size_t index = 1;
                for (auto it = self.read().synonyms_begin(term);
                     it != self.read().synonyms_end(term); ++it, ++index) {
                    out[index] = std::string(*it);
                }
                return out;
            });
        },
        "synonym-keys", [lua](XapianDb& self, sol::optional<std::string> prefix_opt) {
            return xapian_call("synonym-keys", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                std::string prefix = prefix_opt.value_or(std::string());
                size_t index = 1;
                for (auto it = self.read().synonym_keys_begin(prefix);
                     it != self.read().synonym_keys_end(prefix); ++it, ++index) {
                    out[index] = std::string(*it);
                }
                return out;
            });
        },
        "spellings", [lua](XapianDb& self) {
            return xapian_call("spellings", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                size_t index = 1;
                for (auto it = self.read().spellings_begin();
                     it != self.read().spellings_end(); ++it, ++index) {
                    out[index] = std::string(*it);
                }
                return out;
            });
        },
        "allterms", [lua](XapianDb& self, sol::optional<std::string> prefix_opt) {
            return xapian_call("allterms", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                size_t index = 1;
                std::string prefix = prefix_opt.value_or(std::string());
                for (auto it = self.read().allterms_begin(prefix);
                     it != self.read().allterms_end(prefix); ++it, ++index) {
                    out[index] = std::string(*it);
                }
                return out;
            });
        },
        "termlist", [lua](XapianDb& self, Xapian::docid id, sol::optional<sol::table> opts_opt) {
            return xapian_call("termlist", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table opts = opts_opt.value_or(lua_view.create_table());
                bool include_positions = opts.get_or("positions", false);
                sol::table out = lua_view.create_table();
                size_t index = 1;
                for (auto it = self.read().termlist_begin(id);
                     it != self.read().termlist_end(id); ++it, ++index) {
                    sol::table item = lua_view.create_table();
                    item["term"] = std::string(*it);
                    item["wdf"] = it.get_wdf();
                    item["termfreq"] = it.get_termfreq();
                    item["positions-count"] = it.positionlist_count();
                    if (include_positions) {
                        sol::table positions = lua_view.create_table();
                        size_t pindex = 1;
                        for (auto pit = it.positionlist_begin();
                             pit != it.positionlist_end(); ++pit, ++pindex) {
                            positions[pindex] = *pit;
                        }
                        item["positions"] = positions;
                    }
                    out[index] = item;
                }
                return out;
            });
        },
        "positions", [lua](XapianDb& self, Xapian::docid id, const std::string& term) {
            return xapian_call("positions", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table out = lua_view.create_table();
                size_t index = 1;
                for (auto it = self.read().positionlist_begin(id, term);
                     it != self.read().positionlist_end(id, term); ++it, ++index) {
                    out[index] = *it;
                }
                return out;
            });
        },
        "postings", [lua](XapianDb& self, const std::string& term,
                          sol::optional<sol::table> opts_opt) {
            return xapian_call("postings", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table opts = opts_opt.value_or(lua_view.create_table());
                bool include_positions = opts.get_or("positions", false);
                int limit = opts.get_or("limit", 0);
                if (limit < 0) {
                    throw sol::error("xapian.postings limit must be non-negative");
                }
                sol::table out = lua_view.create_table();
                size_t index = 1;
                for (auto it = self.read().postlist_begin(term);
                     it != self.read().postlist_end(term); ++it) {
                    if (limit > 0 && static_cast<int>(index) > limit) {
                        break;
                    }
                    sol::table item = lua_view.create_table();
                    item["docid"] = *it;
                    item["wdf"] = it.get_wdf();
                    item["doclength"] = it.get_doclength();
                    item["unique-terms"] = it.get_unique_terms();
                    if (include_positions) {
                        sol::table positions = lua_view.create_table();
                        size_t pindex = 1;
                        for (auto pit = it.positionlist_begin();
                             pit != it.positionlist_end(); ++pit, ++pindex) {
                            positions[pindex] = *pit;
                        }
                        item["positions"] = positions;
                    }
                    out[index] = item;
                    ++index;
                }
                return out;
            });
        },
        "values", [lua](XapianDb& self, Xapian::valueno slot, sol::optional<int> limit_opt) {
            return xapian_call("values", [&]() {
                sol::state_view lua_view(lua.lua_state());
                int limit = limit_opt.value_or(0);
                if (limit < 0) {
                    throw sol::error("xapian.values limit must be non-negative");
                }
                sol::table out = lua_view.create_table();
                size_t index = 1;
                for (auto it = self.read().valuestream_begin(slot);
                     it != self.read().valuestream_end(slot); ++it) {
                    if (limit > 0 && static_cast<int>(index) > limit) {
                        break;
                    }
                    sol::table item = lua_view.create_table();
                    item["docid"] = it.get_docid();
                    item["value"] = std::string(*it);
                    out[index] = item;
                    ++index;
                }
                return out;
            });
        },
        "get-document", [lua](XapianDb& self, Xapian::docid id) {
            return xapian_call("get-document", [&]() {
                Xapian::Document doc = self.read().get_document(id);
                return document_to_table(lua, doc);
            });
        },
        "search", [lua](XapianDb& self, const std::string& query, sol::optional<sol::table> opts_opt) {
            return xapian_call("search", [&]() {
                sol::state_view lua_view(lua.lua_state());
                sol::table opts = opts_opt.value_or(lua_view.create_table());
                Xapian::QueryParser parser;
                parser.set_database(self.read());
                parser.set_default_op(parse_default_op(opts.get<sol::optional<std::string>>("default-op")));
                if (auto stemmer = opts.get<sol::optional<std::string>>("stemmer")) {
                    parser.set_stemmer(Xapian::Stem(*stemmer));
                }
                auto range_specs = parse_range_processors(opts.get<sol::optional<sol::table>>("ranges"));
                for (const auto& spec : range_specs) {
                    if (spec.kind == "number") {
                        if (spec.prefix.empty()) {
                            parser.add_rangeprocessor((new Xapian::NumberRangeProcessor(spec.slot,
                                std::string(), spec.flags))->release());
                        } else {
                            parser.add_rangeprocessor((new Xapian::NumberRangeProcessor(spec.slot,
                                spec.prefix, spec.flags))->release());
                        }
                    } else if (spec.kind == "date") {
                        if (spec.prefix.empty()) {
                            parser.add_rangeprocessor((new Xapian::DateRangeProcessor(spec.slot,
                                spec.flags, spec.epoch_year))->release());
                        } else {
                            parser.add_rangeprocessor((new Xapian::DateRangeProcessor(spec.slot,
                                spec.prefix, spec.flags, spec.epoch_year))->release());
                        }
                    } else {
                        throw sol::error("xapian.search ranges unknown type: " + spec.kind);
                    }
                }
                auto prefixes = parse_prefix_list(opts.get<sol::optional<sol::table>>("prefixes"),
                                                  "prefixes");
                auto boolean_prefixes = parse_prefix_list(
                    opts.get<sol::optional<sol::table>>("boolean-prefixes"),
                    "boolean-prefixes");
                for (const auto& spec : prefixes) {
                    parser.add_prefix(spec.field, spec.prefix);
                }
                for (const auto& spec : boolean_prefixes) {
                    parser.add_boolean_prefix(spec.field, spec.prefix);
                }

                unsigned flags = parse_query_flags(opts.get<sol::optional<sol::object>>("flags"));
                Xapian::Query parsed = parser.parse_query(query, flags);
                sol::optional<bool> include_corrected = opts.get<sol::optional<bool>>("include-corrected");
                std::string corrected_query;
                if (include_corrected && *include_corrected) {
                    corrected_query = parser.get_corrected_query_string();
                }
                sol::optional<bool> include_stoplist = opts.get<sol::optional<bool>>("include-stoplist");
                sol::optional<bool> include_unstem = opts.get<sol::optional<bool>>("include-unstem");
                Xapian::Query filtered = parsed;
                auto filters = parse_boolean_filters(opts.get<sol::optional<sol::table>>("boolean-filters"));
                for (const auto& filter : filters) {
                    Xapian::Query term_query(filter.prefix + filter.value);
                    filtered = Xapian::Query(Xapian::Query::OP_FILTER, filtered, term_query);
                }
                auto ranges = parse_value_ranges(opts.get<sol::optional<sol::table>>("value-ranges"));
                for (const auto& range : ranges) {
                    Xapian::Query range_query(Xapian::Query::OP_VALUE_RANGE, range.slot,
                                              range.start, range.end);
                    filtered = Xapian::Query(Xapian::Query::OP_FILTER, filtered, range_query);
                }
                Xapian::Enquire enquire(self.read());
                enquire.set_query(filtered);
                if (auto weighting = parse_weighting(opts.get<sol::optional<sol::object>>("weighting"))) {
                    enquire.set_weighting_scheme(*weighting);
                }
                if (auto sort_spec = parse_sort_spec(opts.get<sol::optional<sol::table>>("sort"))) {
                    if (sort_spec->then_relevance) {
                        enquire.set_sort_by_value_then_relevance(sort_spec->slot, sort_spec->descending);
                    } else {
                        enquire.set_sort_by_value(sort_spec->slot, sort_spec->descending);
                    }
                }
                if (auto collapse_spec = parse_collapse_spec(opts.get<sol::optional<sol::table>>("collapse"))) {
                    enquire.set_collapse_key(collapse_spec->slot, collapse_spec->max);
                }
                std::vector<Xapian::docid> rset_docids = parse_docids(
                    opts.get<sol::optional<sol::table>>("rset"),
                    "rset");

                int limit = opts.get_or("limit", 10);
                int offset = opts.get_or("offset", 0);
                if (limit < 0 || offset < 0) {
                    throw sol::error("xapian.search limit/offset must be non-negative");
                }
                Xapian::RSet rset;
                const Xapian::RSet* rset_ptr = nullptr;
                if (!rset_docids.empty()) {
                    for (auto docid : rset_docids) {
                        rset.add_document(docid);
                    }
                    rset_ptr = &rset;
                }
                Xapian::MSet matches = enquire.get_mset(static_cast<size_t>(offset),
                                                       static_cast<size_t>(limit), rset_ptr);

                sol::table out = lua_view.create_table();
                out["estimated"] = matches.get_matches_estimated();
                out["count"] = matches.size();
                if (!corrected_query.empty()) {
                    out["corrected"] = corrected_query;
                }
                if (include_stoplist && *include_stoplist) {
                    sol::table stoplist = lua_view.create_table();
                    size_t sindex = 1;
                    for (auto it = parser.stoplist_begin();
                         it != parser.stoplist_end(); ++it, ++sindex) {
                        stoplist[sindex] = std::string(*it);
                    }
                    out["stoplist"] = stoplist;
                }
                if (include_unstem && *include_unstem) {
                    sol::table unstem = lua_view.create_table();
                    for (auto it = parsed.get_unique_terms_begin();
                         it != parsed.get_unique_terms_end(); ++it) {
                        const std::string term = *it;
                        sol::table forms = lua_view.create_table();
                        size_t findex = 1;
                        for (auto uit = parser.unstem_begin(term);
                             uit != parser.unstem_end(term); ++uit, ++findex) {
                            forms[findex] = std::string(*uit);
                        }
                        if (findex > 1) {
                            unstem[term] = forms;
                        }
                    }
                    out["unstem"] = unstem;
                }

                sol::table items = lua_view.create_table();
                size_t index = 1;
                for (auto it = matches.begin(); it != matches.end(); ++it, ++index) {
                    sol::table item = lua_view.create_table();
                    item["docid"] = *it;
                    item["rank"] = it.get_rank();
                    item["percent"] = it.get_percent();
                    item["score"] = it.get_weight();
                    Xapian::Document doc = it.get_document();
                    item["data"] = doc.get_data();
                    sol::table values = lua_view.create_table();
                    for (auto vit = doc.values_begin(); vit != doc.values_end(); ++vit) {
                        values[vit.get_valueno()] = std::string(*vit);
                    }
                    item["values"] = values;
                    if (opts.get_or("include-collapse", false)) {
                        item["collapse-count"] = it.get_collapse_count();
                        item["collapse-key"] = it.get_collapse_key();
                    }
                    if (opts.get_or("include-sort-key", false)) {
                        item["sort-key"] = it.get_sort_key();
                    }
                    if (opts.get_or("include-matching-terms", false)) {
                        sol::table terms = lua_view.create_table();
                        size_t tindex = 1;
                        for (auto tit = enquire.get_matching_terms_begin(it);
                             tit != enquire.get_matching_terms_end(it); ++tit, ++tindex) {
                            terms[tindex] = std::string(*tit);
                        }
                        item["matching-terms"] = terms;
                    }
                    items[index] = item;
                }
                out["matches"] = items;

                if (auto expand = parse_expand_options(opts.get<sol::optional<sol::table>>("expand"))) {
                    Xapian::RSet rset;
                    for (auto docid : expand->docids) {
                        rset.add_document(docid);
                    }
                    Xapian::ESet eset = enquire.get_eset(expand->limit, rset, expand->flags, nullptr,
                                                        expand->min_weight);
                    sol::table expand_out = lua_view.create_table();
                    expand_out["count"] = eset.size();
                    expand_out["estimated"] = eset.get_ebound();
                    sol::table terms = lua_view.create_table();
                    size_t tindex = 1;
                    for (auto it = eset.begin(); it != eset.end(); ++it, ++tindex) {
                        sol::table item = lua_view.create_table();
                        item["term"] = *it;
                        item["weight"] = it.get_weight();
                        terms[tindex] = item;
                    }
                    expand_out["terms"] = terms;
                    out["expanded"] = expand_out;
                }
                return out;
            });
        }
    );

    xapian.set_function("document", [](sol::optional<sol::table> opts_opt) {
        return build_document(opts_opt);
    });

    xapian.set_function("open", [](const std::string& path, sol::optional<sol::table> opts_opt) {
        bool writable = false;
        bool create = false;
        bool overwrite = false;
        if (opts_opt) {
            sol::table opts = *opts_opt;
            writable = opts.get_or("writable", false);
            create = opts.get_or("create", false);
            overwrite = opts.get_or("overwrite", false);
        }
        if (!writable && (create || overwrite)) {
            throw sol::error("xapian.open create options require writable=true");
        }
        if (writable) {
            int flags = Xapian::DB_OPEN;
            if (overwrite) {
                flags = Xapian::DB_CREATE_OR_OVERWRITE;
            } else if (create) {
                flags = Xapian::DB_CREATE_OR_OPEN;
            }
            return xapian_call("open", [&]() {
                auto db = std::make_unique<Xapian::WritableDatabase>(path, flags);
                return std::make_shared<XapianDb>(std::move(db));
            });
        }
        return xapian_call("open", [&]() {
            auto db = std::make_unique<Xapian::Database>(path);
            return std::make_shared<XapianDb>(std::move(db));
        });
    });

    xapian.set_function("version", []() {
        return std::string(Xapian::version_string());
    });

    xapian.set_function("sortable-serialise", [](double value) {
        return Xapian::sortable_serialise(value);
    });

    return xapian;
}

} // namespace

void lua_bind_xapian(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("xapian", [](sol::this_state state) {
        sol::state_view lua_view(state);
        return create_xapian_table(lua_view);
    });
}
