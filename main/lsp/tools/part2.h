class FieldDef final {
public:
    const std::string jsonName;
    const std::string cppName;
    std::shared_ptr<JSONType> type;

    FieldDef(std::string_view name, std::shared_ptr<JSONType> type)
        : jsonName(std::string(name)), cppName(std::string(name)), type(type) {}
    FieldDef(std::string_view jsonName, std::string_view cppName, std::shared_ptr<JSONType> type)
        : jsonName(jsonName), cppName(cppName), type(type) {}

    void emitDeclaration(fmt::memory_buffer &out) const {
        fmt::format_to(std::back_inserter(out), "{} {};\n", type->getCPPType(), cppName);
    }
};

class JSONOptionalType final : public JSONType {
private:
    std::shared_ptr<JSONType> innerType;

public:
    JSONOptionalType(std::shared_ptr<JSONType> innerType) : innerType(innerType) {}

    BaseKind getCPPBaseKind() const {
        return BaseKind::ComplexKind;
    }

    BaseKind getJSONBaseKind() const {
        return BaseKind::ComplexKind;
    }

    std::string getCPPType() const {
        return fmt::format("std::optional<{}>", innerType->getCPPType());
    }

    std::string getJSONType() const {
        return fmt::format("({})?", innerType->getJSONType());
    }

    bool wantMove() const {
        return innerType->wantMove();
    }

    void emitFromJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                           std::string_view fieldName) {
        // Check for presence of field.
        // N.B.: Treat null fields as missing. Emacs fills in optional fields with `null` values.
        fmt::format_to(std::back_inserter(out), "if ({0} && !(*{0})->IsNull()) {{\n", from);
        const std::string innerCPPType = innerType->getCPPType();
        AssignLambda assignOptional = [innerCPPType, assign](fmt::memory_buffer &out, std::string_view from) -> void {
            assign(out, fmt::format("std::make_optional<{}>({})", innerCPPType, from));
        };
        innerType->emitFromJSONValue(out, from, assignOptional, fieldName);
        fmt::format_to(std::back_inserter(out), "}} else {{\n");
        // Ensures that optional is assigned to correct variant slot on variant types, since optional<Foo> !=
        // optional<Bar>.
        assign(out, fmt::format("std::optional<{}>(std::nullopt)", innerCPPType));
        fmt::format_to(std::back_inserter(out), "}}\n");
    }

    void emitToJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                         std::string_view fieldName) {
        fmt::format_to(std::back_inserter(out), "if ({}.has_value()) {{\n", from);
        // N.B.: Mac OSX does not support .value() on std::optional yet.
        // Dereferencing does the same thing, but does not check if the value is present.
        // But since we explicitly check `has_value()`, we're good here.
        // See: https://stackoverflow.com/a/44244070
        innerType->emitToJSONValue(out, fmt::format("(*{})", from), assign, fieldName);
        fmt::format_to(std::back_inserter(out), "}}\n");
    }
};

class JSONObjectType final : public JSONClassType {
private:
    std::vector<std::string> extraMethodDefinitions;
    std::vector<std::shared_ptr<FieldDef>> fieldDefs;
    std::vector<std::shared_ptr<FieldDef>> getRequiredFields() {
        std::vector<std::shared_ptr<FieldDef>> reqFields;
        // Filter out optional fields.
        std::copy_if(fieldDefs.begin(), fieldDefs.end(), std::back_inserter(reqFields),
                     [](auto &fieldDef) { return !dynamic_cast<JSONOptionalType *>(fieldDef->type.get()); });
        return reqFields;
    }

public:
    JSONObjectType(std::string_view typeName, std::vector<std::shared_ptr<FieldDef>> fieldDefs,
                   std::vector<std::string> extraMethodDefinitions)
        : JSONClassType(typeName), extraMethodDefinitions(extraMethodDefinitions), fieldDefs(fieldDefs) {}

    BaseKind getCPPBaseKind() const {
        return BaseKind::ObjectKind;
    }

    BaseKind getJSONBaseKind() const {
        return BaseKind::ObjectKind;
    }

    std::string getCPPType() const {
        return fmt::format("std::unique_ptr<{}>", typeName);
    }

    std::string getJSONType() const {
        return typeName;
    }

    bool wantMove() const {
        return true;
    }

    void emitFromJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                           std::string_view fieldName) {
        assign(out,
               fmt::format("{0}::fromJSONValue(assertJSONField({1}, \"{2}\"), \"{2}\")", typeName, from, fieldName));
    }

    void emitToJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                         std::string_view fieldName) {
        fmt::format_to(std::back_inserter(out), "if ({} == nullptr) {{\n", from);
        fmt::format_to(std::back_inserter(out), "throw NullPtrError(\"{}\");\n", fieldName);
        fmt::format_to(std::back_inserter(out), "}}\n");
        assign(out, fmt::format("*({}->toJSONValue({}))", from, ALLOCATOR_VAR));
    }

    void emitDeclaration(fmt::memory_buffer &out) {
        fmt::format_to(std::back_inserter(out), "class {} final : public JSONBaseType {{\n", typeName);
        fmt::format_to(std::back_inserter(out), "public:\n");
        fmt::format_to(std::back_inserter(out),
                       "static {} fromJSONValue(const rapidjson::Value &val, std::string_view fieldName = "
                       "JSONBaseType::defaultFieldName);\n",
                       getCPPType());
        for (std::shared_ptr<FieldDef> &fieldDef : fieldDefs) {
            fieldDef->emitDeclaration(out);
        }
        auto reqFields = getRequiredFields();
        if (reqFields.size() > 0) {
            // Constructor. Only accepts non-optional fields as arguments
            fmt::format_to(std::back_inserter(out), "{}({});\n", typeName,
                           fmt::map_join(getRequiredFields(), ", ", [](auto field) -> std::string {
                               return fmt::format("{} {}", field->type->getCPPType(), field->cppName);
                           }));
        }
        fmt::format_to(
            std::back_inserter(out),
            "std::unique_ptr<rapidjson::Value> toJSONValue(rapidjson::MemoryPoolAllocator<> &alloc) const;\n");
        fmt::format_to(std::back_inserter(out), "{}\n",
                       fmt::join(extraMethodDefinitions.begin(), extraMethodDefinitions.end(), "\n"));
        fmt::format_to(std::back_inserter(out), "}};\n");
    }

    void emitDefinition(fmt::memory_buffer &out) {
        auto reqFields = getRequiredFields();
        if (reqFields.size() > 0) {
            fmt::format_to(std::back_inserter(out), "{}::{}({}): {} {{\n", typeName, typeName,
                           fmt::map_join(reqFields, ", ",
                                         [](auto field) -> std::string {
                                             return fmt::format("{} {}", field->type->getCPPType(), field->cppName);
                                         }),
                           fmt::map_join(reqFields, ", ", [](auto field) -> std::string {
                               if (field->type->wantMove()) {
                                   return fmt::format("{}(move({}))", field->cppName, field->cppName);
                               }
                               return fmt::format("{}({})", field->cppName, field->cppName);
                           }));
            fmt::format_to(std::back_inserter(out), "}}\n");
        }
        fmt::format_to(std::back_inserter(out),
                       "{} {}::fromJSONValue(const rapidjson::Value &val, std::string_view fieldName) {{\n",
                       getCPPType(), typeName);
        fmt::format_to(std::back_inserter(out), "if (!val.IsObject()) {{\n");
        fmt::format_to(std::back_inserter(out), "throw JSONTypeError(fieldName, \"object\", val);\n");
        fmt::format_to(std::back_inserter(out), "}}\n");

        // Process required fields first.
        for (std::shared_ptr<FieldDef> &fieldDef : reqFields) {
            std::string fieldName = fmt::format("{}.{}", typeName, fieldDef->cppName);
            fmt::format_to(std::back_inserter(out), "auto rapidjson{} = maybeGetJSONField(val, \"{}\");\n",
                           fieldDef->cppName, fieldDef->jsonName);
            fmt::format_to(std::back_inserter(out), "{} {};\n", fieldDef->type->getCPPType(), fieldDef->cppName);
            AssignLambda assign = [&fieldDef](fmt::memory_buffer &out, std::string_view from) -> void {
                fmt::format_to(std::back_inserter(out), "{} = {};\n", fieldDef->cppName, from);
            };
            fieldDef->type->emitFromJSONValue(out, fmt::format("rapidjson{}", fieldDef->cppName), assign, fieldName);
        }
        fmt::format_to(std::back_inserter(out), "{} rv = std::make_unique<{}>({});\n", getCPPType(), typeName,
                       fmt::map_join(reqFields, ", ", [](auto field) -> std::string {
                           if (field->type->wantMove()) {
                               return fmt::format("move({})", field->cppName);
                           } else {
                               return field->cppName;
                           }
                       }));

        // Assign optionally specified fields.
        for (std::shared_ptr<FieldDef> &fieldDef : fieldDefs) {
            if (dynamic_cast<JSONOptionalType *>(fieldDef->type.get())) {
                std::string fieldName = fmt::format("{}.{}", typeName, fieldDef->cppName);
                fmt::format_to(std::back_inserter(out), "auto rapidjson{} = maybeGetJSONField(val, \"{}\");\n",
                               fieldDef->cppName, fieldDef->jsonName);
                AssignLambda assign = [&fieldDef](fmt::memory_buffer &out, std::string_view from) -> void {
                    fmt::format_to(std::back_inserter(out), "rv->{} = {};\n", fieldDef->cppName, from);
                };
                fieldDef->type->emitFromJSONValue(out, fmt::format("rapidjson{}", fieldDef->cppName), assign,
                                                  fieldName);
            }
        }
        fmt::format_to(std::back_inserter(out), "return rv;\n");
        fmt::format_to(std::back_inserter(out), "}}\n");

        fmt::format_to(std::back_inserter(out),
                       "std::unique_ptr<rapidjson::Value> {}::toJSONValue(rapidjson::MemoryPoolAllocator<> "
                       "&{}) const {{\n",
                       typeName, ALLOCATOR_VAR);
        fmt::format_to(std::back_inserter(out),
                       "auto rv = std::make_unique<rapidjson::Value>(rapidjson::kObjectType);\n");
        for (std::shared_ptr<FieldDef> &fieldDef : fieldDefs) {
            std::string fieldName = fmt::format("{}.{}", typeName, fieldDef->cppName);
            AssignLambda assign = [&fieldDef](fmt::memory_buffer &out, std::string_view from) -> void {
                fmt::format_to(std::back_inserter(out), "rv->AddMember(\"{}\", {}, {});\n", fieldDef->jsonName, from,
                               ALLOCATOR_VAR);
            };
            fieldDef->type->emitToJSONValue(out, fieldDef->cppName, assign, fieldName);
        }
        fmt::format_to(std::back_inserter(out), "return rv;\n");
        fmt::format_to(std::back_inserter(out), "}}\n");
    }

    /**
     * Add in a field post-definition. Used to support
     * object types that have fields of their own type.
     */
    void addField(std::shared_ptr<FieldDef> field) {
        fieldDefs.push_back(field);
    }
};

/**
 * Abstract class. Implements basic functionality for any field that can contain one or more different types of data.
 */
class JSONVariantType : public JSONType {
protected:
    std::vector<std::shared_ptr<JSONType>> variants;

public:
    JSONVariantType(std::vector<std::shared_ptr<JSONType>> variants) : variants(variants) {}

    BaseKind getCPPBaseKind() const {
        return BaseKind::ComplexKind;
    }

    BaseKind getJSONBaseKind() const {
        return BaseKind::ComplexKind;
    }

    std::string getCPPType() const {
        // Variants cannot contain duplicate types, so dedupe the CPP types.
        // Have order match order in `variants` (which matches declaration order) to avoid surprises.
        UnorderedSet<std::string> uniqueTypes;
        std::vector<std::string> emitOrder;
        for (auto &variant : variants) {
            auto cppType = variant->getCPPType();
            if (!uniqueTypes.contains(cppType)) {
                uniqueTypes.insert(cppType);
                emitOrder.push_back(cppType);
            }
        }
        return fmt::format("std::variant<{}>", fmt::join(emitOrder, ","));
    }

    std::string getJSONType() const {
        return fmt::format(
            "{}", fmt::map_join(variants, " | ", [](auto variant) -> std::string { return variant->getJSONType(); }));
    }

    bool wantMove() const {
        for (auto &variant : variants) {
            if (variant->wantMove()) {
                return true;
            }
        }
        return false;
    }
};

/**
 * A 'discriminated union' type is a variant type where some other field on the object
 * determines its true type.
 */
class JSONDiscriminatedUnionVariantType final : public JSONVariantType {
private:
    std::shared_ptr<FieldDef> fieldDef;
    const std::vector<std::pair<const std::string, std::shared_ptr<JSONType>>> variantsByDiscriminant;

    static std::vector<std::shared_ptr<JSONType>>
    getVariantTypes(const std::vector<std::pair<const std::string, std::shared_ptr<JSONType>>> &variants) {
        std::vector<std::shared_ptr<JSONType>> rv;
        rv.reserve(variants.size());
        for (auto &variant : variants) {
            rv.push_back(variant.second);
        }
        return rv;
    }

    JSONStringEnumType *getDiscriminantType() {
        auto enumType = dynamic_cast<JSONStringEnumType *>(fieldDef->type.get());
        if (!enumType) {
            throw std::invalid_argument("The discriminant for a discriminated union must be a string enum.");
        }
        return enumType;
    }

public:
    JSONDiscriminatedUnionVariantType(
        std::shared_ptr<FieldDef> fieldDef,
        const std::vector<std::pair<const std::string, std::shared_ptr<JSONType>>> variantsByDiscriminant)
        : JSONVariantType(getVariantTypes(variantsByDiscriminant)), fieldDef(fieldDef),
          variantsByDiscriminant(variantsByDiscriminant) {}

    void emitFromJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                           std::string_view fieldName) {
        auto enumType = getDiscriminantType();
        fmt::format_to(std::back_inserter(out), "switch ({}) {{\n", fieldDef->cppName);
        for (auto &variant : variantsByDiscriminant) {
            // getEnumValue will throw if the discriminant value is not in the enum.
            fmt::format_to(std::back_inserter(out), "case {}:\n", enumType->getEnumValue(variant.first));
            variant.second->emitFromJSONValue(out, from, assign, fieldName);
            fmt::format_to(std::back_inserter(out), "break;\n");
        }
        fmt::format_to(std::back_inserter(out), "default:\n");
        fmt::format_to(std::back_inserter(out),
                       "throw InvalidDiscriminantValueError(\"{0}\", \"{1}\", convert{2}ToString({1}));\n", fieldName,
                       fieldDef->cppName, enumType->getCPPType());
        fmt::format_to(std::back_inserter(out), "}}\n");
    }

    void emitToJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                         std::string_view fieldName) {
        auto enumType = getDiscriminantType();
        fmt::format_to(std::back_inserter(out), "switch ({}) {{\n", fieldDef->cppName);
        for (auto &variant : variantsByDiscriminant) {
            // getEnumValue will throw if the discriminant value is not in the enum.
            fmt::format_to(std::back_inserter(out), "case {}:\n", enumType->getEnumValue(variant.first));
            fmt::format_to(std::back_inserter(out), "if (auto discVal = std::get_if<{}>(&{})) {{\n",
                           variant.second->getCPPType(), from);
            variant.second->emitToJSONValue(out, "(*discVal)", assign, fieldName);
            fmt::format_to(std::back_inserter(out), "}} else {{\n");
            fmt::format_to(
                std::back_inserter(out),
                "throw InvalidDiscriminatedUnionValueError(\"{0}\", \"{1}\", convert{2}ToString({1}), \"{3}\");\n",
                fieldName, fieldDef->cppName, enumType->getCPPType(), variant.second->getCPPType());
            fmt::format_to(std::back_inserter(out), "}}\n");
            fmt::format_to(std::back_inserter(out), "break;\n");
        }
        fmt::format_to(std::back_inserter(out), "default:\n");
        fmt::format_to(std::back_inserter(out),
                       "throw InvalidDiscriminantValueError(\"{0}\", \"{1}\", convert{2}ToString({1}));\n", fieldName,
                       fieldDef->cppName, enumType->getCPPType());
        fmt::format_to(std::back_inserter(out), "}}\n");
    }
};

class JSONBasicVariantType final : public JSONVariantType {
    bool allowFallThrough;

public:
    // By default, we do not allow overlapping JSON base types, because it might indicate that the
    // user messed something up.
    //
    // But if we acknowledge the risks, it's useful for representing types like "either a known
    // string literal, or any string" (e.g. an open enum)
    JSONBasicVariantType(std::vector<std::shared_ptr<JSONType>> variants, bool allowFallThrough = false)
        : JSONVariantType(variants), allowFallThrough(allowFallThrough) {
        // Check that we have at most one of every kind & do not have any complex types.
        UnorderedSet<BaseKind> cppKindSeen;
        UnorderedSet<BaseKind> jsonKindSeen;
        for (std::shared_ptr<JSONType> variant : variants) {
            if (variant->getCPPBaseKind() == BaseKind::ComplexKind ||
                variant->getJSONBaseKind() == BaseKind::ComplexKind) {
                throw std::invalid_argument("Invalid variant type: Complex are not supported.");
            }

            if (cppKindSeen.contains(variant->getCPPBaseKind())) {
                throw std::invalid_argument(
                    "Invalid variant type: Cannot discriminate between multiple types with same base C++ kind.");
            }
            cppKindSeen.insert(variant->getCPPBaseKind());

            if (!allowFallThrough) {
                if (jsonKindSeen.contains(variant->getJSONBaseKind())) {
                    throw std::invalid_argument(
                        "Invalid variant type: Cannot discriminate between multiple types with same base JSON kind.");
                }
            }
            jsonKindSeen.insert(variant->getJSONBaseKind());
        }
    }

    void emitFromJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                           std::string_view fieldName) {
        if (allowFallThrough) {
            for (std::shared_ptr<JSONType> variant : variants) {
                fmt::format_to(std::back_inserter(out), "try {{\n");
                variant->emitFromJSONValue(out, from, assign, fieldName);
                fmt::format_to(std::back_inserter(out), "}} catch (const DeserializationError &e) {{\n");
            }

            fmt::format_to(std::back_inserter(out), "auto &unwrappedValue = assertJSONField({}, \"{}\");", from,
                           fieldName);
            fmt::format_to(std::back_inserter(out), "throw JSONTypeError(\"{}\", \"{}\", unwrappedValue);\n", fieldName,
                           sorbet::JSON::escape(getJSONType()));

            for (std::shared_ptr<JSONType> variant : variants) {
                fmt::format_to(std::back_inserter(out), "}}\n");
            }
        } else {
            fmt::format_to(std::back_inserter(out), "{{\n");
            fmt::format_to(std::back_inserter(out), "auto &unwrappedValue = assertJSONField({}, \"{}\");", from,
                           fieldName);
            bool first = true;
            for (std::shared_ptr<JSONType> variant : variants) {
                std::string checkMethod;
                switch (variant->getJSONBaseKind()) {
                    case BaseKind::NullKind:
                        checkMethod = "IsNull";
                        break;
                    case BaseKind::BooleanKind:
                        checkMethod = "IsBool";
                        break;
                    case BaseKind::IntKind:
                        checkMethod = "IsInt";
                        break;
                    case BaseKind::DoubleKind:
                        // N.B.: IsDouble() returns false for integers.
                        // We only care that the value is convertible to double, which is what IsNumber tests.
                        checkMethod = "IsNumber";
                        break;
                    case BaseKind::StringKind:
                        checkMethod = "IsString";
                        break;
                    case BaseKind::ObjectKind:
                        checkMethod = "IsObject";
                        break;
                    case BaseKind::ArrayKind:
                        checkMethod = "IsArray";
                        break;
                    default:
                        throw std::invalid_argument("Invalid kind for variant type.");
                }
                auto condition = fmt::format("unwrappedValue.{}()", checkMethod);
                if (first) {
                    first = false;
                    fmt::format_to(std::back_inserter(out), "if ({}) {{\n", condition);
                } else {
                    fmt::format_to(std::back_inserter(out), "}} else if ({}) {{\n", condition);
                }
                variant->emitFromJSONValue(out, from, assign, fieldName);
            }
            fmt::format_to(std::back_inserter(out), "}} else {{\n");
            fmt::format_to(std::back_inserter(out), "throw JSONTypeError(\"{}\", \"{}\", unwrappedValue);\n", fieldName,
                           sorbet::JSON::escape(getJSONType()));
            fmt::format_to(std::back_inserter(out), "}}\n");
            fmt::format_to(std::back_inserter(out), "}}\n");
        }
    }

    void emitToJSONValue(fmt::memory_buffer &out, std::string_view from, AssignLambda assign,
                         std::string_view fieldName) {
        bool first = true;
        for (std::shared_ptr<JSONType> variant : variants) {
            auto condition = fmt::format("auto val = std::get_if<{}>(&{})", variant->getCPPType(), from);
            if (first) {
                first = false;
                fmt::format_to(std::back_inserter(out), "if ({}) {{\n", condition);
            } else {
                fmt::format_to(std::back_inserter(out), "}} else if ({}) {{\n", condition);
            }
            variant->emitToJSONValue(out, "(*val)", assign, fieldName);
        }
        fmt::format_to(std::back_inserter(out), "}} else {{\n");
        fmt::format_to(std::back_inserter(out), "throw MissingVariantValueError(\"{}\");\n", fieldName);
        fmt::format_to(std::back_inserter(out), "}}\n");
    }
};

#endif // GENERATE_LSP_MESSAGES_H
