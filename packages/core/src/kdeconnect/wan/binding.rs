//! Persistent `kdeDeviceId -> irohEndpointId` binding registry.
//!
//! A WAN `EndpointId` becomes trusted *only* by being present here. Pairing
//! itself always happens over an already-trusted KDE LAN connection (today on
//! the Android side); this registry is the desktop-side storage/lookup half of
//! that exchange. An `EndpointId` that merely claims a known KDE device id in
//! its hello is never sufficient on its own -- see [`super::runtime::WanRuntime::accept_one`].

use std::collections::HashMap;
use std::sync::Mutex;

use iroh::EndpointId;

/// One persisted WAN binding. Storage/persistence of the `Vec<WanBinding>`
/// itself is the host platform's responsibility (mirroring how
/// [`crate::kdeconnect::TrustedDevice`] is persisted by Dart, not by this
/// crate) -- this type is the in-memory, query-optimized runtime view.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WanBinding {
    pub kde_device_id: String,
    pub endpoint_id: EndpointId,
    pub display_name: String,
    pub device_type: String,
    pub capabilities: Vec<String>,
    pub binding_version: i64,
    pub updated_at_unix: i64,
    pub last_wan_connected_at_unix: Option<i64>,
    pub last_transport: Option<String>,
}

/// In-memory registry mapping KDE device ids to Iroh `EndpointId`s in both
/// directions. Constructed from a persisted snapshot at startup, mutated at
/// runtime, and read back out via [`Self::snapshot`] for the host to persist.
#[derive(Default)]
pub struct WanBindingRegistry {
    by_device: Mutex<HashMap<String, WanBinding>>,
}

impl WanBindingRegistry {
    pub fn new(initial: Vec<WanBinding>) -> Self {
        let mut by_device = HashMap::with_capacity(initial.len());
        for binding in initial {
            by_device.insert(binding.kde_device_id.clone(), binding);
        }
        Self {
            by_device: Mutex::new(by_device),
        }
    }

    pub fn upsert(&self, binding: WanBinding) {
        self.by_device
            .lock()
            .expect("WanBindingRegistry mutex poisoned")
            .insert(binding.kde_device_id.clone(), binding);
    }

    pub fn remove(&self, kde_device_id: &str) -> Option<WanBinding> {
        self.by_device
            .lock()
            .expect("WanBindingRegistry mutex poisoned")
            .remove(kde_device_id)
    }

    pub fn by_kde_device_id(&self, kde_device_id: &str) -> Option<WanBinding> {
        self.by_device
            .lock()
            .expect("WanBindingRegistry mutex poisoned")
            .get(kde_device_id)
            .cloned()
    }

    /// Looks up a binding by the *authenticated* remote `EndpointId` of an
    /// incoming Iroh connection. Returns `None` for any `EndpointId` this
    /// registry does not already know about -- callers must treat that as an
    /// outright rejection, never as "pair on first contact".
    pub fn by_endpoint_id(&self, endpoint_id: &EndpointId) -> Option<WanBinding> {
        self.by_device
            .lock()
            .expect("WanBindingRegistry mutex poisoned")
            .values()
            .find(|binding| &binding.endpoint_id == endpoint_id)
            .cloned()
    }

    pub fn record_connection(&self, kde_device_id: &str, transport: &str, at_unix: i64) {
        if let Some(binding) = self
            .by_device
            .lock()
            .expect("WanBindingRegistry mutex poisoned")
            .get_mut(kde_device_id)
        {
            binding.last_wan_connected_at_unix = Some(at_unix);
            binding.last_transport = Some(transport.to_owned());
        }
    }

    pub fn snapshot(&self) -> Vec<WanBinding> {
        self.by_device
            .lock()
            .expect("WanBindingRegistry mutex poisoned")
            .values()
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use iroh::SecretKey;

    fn binding(kde_device_id: &str, endpoint_id: EndpointId) -> WanBinding {
        WanBinding {
            kde_device_id: kde_device_id.to_owned(),
            endpoint_id,
            display_name: "Phone".to_owned(),
            device_type: "phone".to_owned(),
            capabilities: vec!["kdeconnect.battery".to_owned()],
            binding_version: 1,
            updated_at_unix: 0,
            last_wan_connected_at_unix: None,
            last_transport: None,
        }
    }

    #[test]
    fn known_endpoint_resolves_to_its_kde_device_id() {
        let endpoint_id = SecretKey::generate().public();
        let registry = WanBindingRegistry::new(vec![binding("device-a", endpoint_id)]);

        let found = registry.by_endpoint_id(&endpoint_id).unwrap();
        assert_eq!(found.kde_device_id, "device-a");
    }

    #[test]
    fn unknown_endpoint_is_rejected() {
        let known = SecretKey::generate().public();
        let unknown = SecretKey::generate().public();
        let registry = WanBindingRegistry::new(vec![binding("device-a", known)]);

        assert!(registry.by_endpoint_id(&unknown).is_none());
    }

    #[test]
    fn empty_registry_rejects_every_endpoint() {
        let registry = WanBindingRegistry::new(vec![]);
        let endpoint_id = SecretKey::generate().public();
        assert!(registry.by_endpoint_id(&endpoint_id).is_none());
    }

    #[test]
    fn recording_a_connection_updates_only_the_matching_binding() {
        let endpoint_a = SecretKey::generate().public();
        let endpoint_b = SecretKey::generate().public();
        let registry = WanBindingRegistry::new(vec![
            binding("device-a", endpoint_a),
            binding("device-b", endpoint_b),
        ]);

        registry.record_connection("device-a", "iroh-direct", 1_700_000_000);

        let a = registry.by_kde_device_id("device-a").unwrap();
        assert_eq!(a.last_wan_connected_at_unix, Some(1_700_000_000));
        assert_eq!(a.last_transport.as_deref(), Some("iroh-direct"));

        let b = registry.by_kde_device_id("device-b").unwrap();
        assert_eq!(b.last_wan_connected_at_unix, None);
    }

    #[test]
    fn rebinding_a_device_to_a_new_endpoint_replaces_the_old_mapping() {
        let old_endpoint = SecretKey::generate().public();
        let new_endpoint = SecretKey::generate().public();
        let registry = WanBindingRegistry::new(vec![binding("device-a", old_endpoint)]);

        registry.upsert(binding("device-a", new_endpoint));

        assert!(registry.by_endpoint_id(&old_endpoint).is_none());
        assert_eq!(
            registry.by_endpoint_id(&new_endpoint).unwrap().kde_device_id,
            "device-a"
        );
        assert_eq!(registry.snapshot().len(), 1);
    }
}
