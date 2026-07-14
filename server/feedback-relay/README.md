# SwiftGibs feedback relay

Receives in-game feedback POSTs from the SwiftGibs client (plain HTTP - the
engine has no TLS) and opens GitHub issues on SalukiSwift/swiftgibs. The
fine-grained, issues-only token lives on the server at
/opt/swiftgibs-feedback/token (mode 600) and never ships in the client.

Flow: game `sendfeedback` -> salukiswift.com:8300/feedback (nginx) ->
127.0.0.1:8301 (this Flask app) -> api.github.com issues.

## Run tests

    python3 test_app.py

(needs flask; no network - the GitHub call is stubbed)

## Deploy (Hetzner box)

    mkdir -p /opt/swiftgibs-feedback
    cp app.py /opt/swiftgibs-feedback/
    python3 -m venv /opt/swiftgibs-feedback/venv
    /opt/swiftgibs-feedback/venv/bin/pip install flask
    # token: copy the fine-grained issues-only token to
    # /opt/swiftgibs-feedback/token, chmod 600
    cp swiftgibs-feedback.service /etc/systemd/system/
    systemctl daemon-reload && systemctl enable --now swiftgibs-feedback
    cp nginx-feedback.conf /etc/nginx/sites-available/swiftgibs-feedback
    ln -s ../sites-available/swiftgibs-feedback /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    ufw allow 8300/tcp

Rate limit: 5 accepted posts per IP per hour (in-memory; restarts reset it).
Issue labels used: in-game-feedback + bug/idea/other (created once via API).
