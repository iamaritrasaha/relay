use std::time::Duration;

use crate::anywhere::{
    authenticate_initiator, authenticate_server, bind_endpoint,
    stream::{
        client_peer_certificate_fingerprint, server_peer_certificate_fingerprint, IrohBiStream,
    },
    InnerTlsPeer, PathPreference,
};
use crate::crypto::relay_identity::RelayIdentity;
use crate::relay::{PathDescriptor, RelayId};
use tokio::time::sleep;

fn direct_path() -> PathDescriptor {
    PathDescriptor::InternetDirect {
        host: String::new(),
        port: None,
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "Iroh ForceDirect datapath is exercised by RA2B crate tests"]
async fn iroh_direct_mutual_auth_and_wrong_identity() {
    let host_identity = RelayIdentity::generate();
    let host_tls = InnerTlsPeer::generate().unwrap();
    let host_endpoint = bind_endpoint(PathPreference::ForceDirect).await.unwrap();
    let host_addr = host_endpoint.addr();
    let host_relay_id = RelayId::from_local_identity(&host_identity).unwrap();
    let host_fp = host_tls.cert_fingerprint;

    let host_task = {
        let host_tls = host_tls.clone();
        tokio::spawn(async move {
            let incoming = host_endpoint.accept().await?;
            let connection = incoming
                .await
                .map_err(|_| crate::anywhere::AnywhereError::Transport)?;
            let (send, recv) = connection
                .accept_bi()
                .await
                .map_err(|_| crate::anywhere::AnywhereError::Transport)?;
            let mut tls = host_tls
                .acceptor()
                .accept(IrohBiStream::new(send, recv))
                .await
                .map_err(|_| crate::anywhere::AnywhereError::Tls)?;
            let observed = server_peer_certificate_fingerprint(&tls)
                .map_err(|_| crate::anywhere::AnywhereError::Tls)?;
            authenticate_server(
                &mut tls,
                &host_identity,
                host_fp,
                None,
                observed,
                direct_path(),
            )
            .await
        })
    };

    sleep(Duration::from_millis(200)).await;

    let join_identity = RelayIdentity::generate();
    let join_tls = InnerTlsPeer::generate().unwrap();
    let join_endpoint = bind_endpoint(PathPreference::ForceDirect).await.unwrap();
    let join_fp = join_tls.cert_fingerprint;
    let connection = join_endpoint.connect(host_addr.clone()).await.unwrap();
    let (send, recv) = connection.open_bi().await.unwrap();
    let server_name = rustls::pki_types::ServerName::try_from("localhost").unwrap();
    let mut tls = join_tls
        .connector()
        .connect(server_name, IrohBiStream::new(send, recv))
        .await
        .unwrap();
    let observed = client_peer_certificate_fingerprint(&tls).unwrap();
    let join_session = authenticate_initiator(
        &mut tls,
        &join_identity,
        join_fp,
        &host_relay_id,
        observed,
        direct_path(),
    )
    .await
    .unwrap();
    let host_session = host_task.await.unwrap().unwrap();
    assert!(join_session.mutual());
    assert!(host_session.mutual());
    assert_ne!(
        join_session.remote_relay_id().as_hex(),
        host_addr.id.to_string()
    );
    join_endpoint.close().await;

    let wrong = RelayId::from_local_identity(&RelayIdentity::generate()).unwrap();
    assert_ne!(wrong.as_hex(), host_relay_id.as_hex());
    let host2 = RelayIdentity::generate();
    let host2_tls = InnerTlsPeer::generate().unwrap();
    let host2_ep = bind_endpoint(PathPreference::ForceDirect).await.unwrap();
    let host2_addr = host2_ep.addr();
    let host2_fp = host2_tls.cert_fingerprint;
    let host2_task = tokio::spawn(async move {
        let incoming = host2_ep.accept().await?;
        let connection = incoming
            .await
            .map_err(|_| crate::anywhere::AnywhereError::Transport)?;
        let (send, recv) = connection
            .accept_bi()
            .await
            .map_err(|_| crate::anywhere::AnywhereError::Transport)?;
        let mut tls = host2_tls
            .acceptor()
            .accept(IrohBiStream::new(send, recv))
            .await
            .map_err(|_| crate::anywhere::AnywhereError::Tls)?;
        let observed = server_peer_certificate_fingerprint(&tls)
            .map_err(|_| crate::anywhere::AnywhereError::Tls)?;
        authenticate_server(&mut tls, &host2, host2_fp, None, observed, direct_path()).await
    });
    sleep(Duration::from_millis(200)).await;
    let join2 = RelayIdentity::generate();
    let join2_tls = InnerTlsPeer::generate().unwrap();
    let join2_ep = bind_endpoint(PathPreference::ForceDirect).await.unwrap();
    let connection = join2_ep.connect(host2_addr).await.unwrap();
    let (send, recv) = connection.open_bi().await.unwrap();
    let server_name = rustls::pki_types::ServerName::try_from("localhost").unwrap();
    let mut tls = join2_tls
        .connector()
        .connect(server_name, IrohBiStream::new(send, recv))
        .await
        .unwrap();
    let observed = client_peer_certificate_fingerprint(&tls).unwrap();
    let err = authenticate_initiator(
        &mut tls,
        &join2,
        join2_tls.cert_fingerprint,
        &wrong,
        observed,
        direct_path(),
    )
    .await
    .unwrap_err();
    assert!(matches!(
        err,
        crate::anywhere::AnywhereError::ExpectedIdentityMismatch { .. }
    ));
    drop(tls);
    let _ = tokio::time::timeout(Duration::from_secs(2), host2_task).await;
}
