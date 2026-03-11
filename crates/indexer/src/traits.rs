use move_core_types::language_storage::StructTag;

/// Trait for matching on-chain Move event struct tags to Rust types.
pub trait MoveStruct {
    /// Returns the expected Move struct tag for this event type.
    fn struct_tag(package: &str, module: &str, name: &str) -> StructTag;

    /// Returns true if the given struct tag matches this event type
    /// across any known package version.
    fn matches(tag: &StructTag, packages: &[String], module: &str, name: &str) -> bool {
        packages.iter().any(|pkg| {
            let expected = Self::struct_tag(pkg, module, name);
            tag.module == expected.module && tag.name == expected.name
        })
    }
}
