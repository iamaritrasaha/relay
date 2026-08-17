use anyhow::Result;
use relay_anywhere_ra2a::run_manual_proof;

#[tokio::main]
async fn main() -> Result<()> {
    let report = run_manual_proof().await?;
    report.print();
    Ok(())
}
