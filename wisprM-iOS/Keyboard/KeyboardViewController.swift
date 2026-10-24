import UIKit
import WisprMobileCore

final class KeyboardViewController: UIInputViewController {
    private var latest: Transcript?
    private let insert = UIButton(type: .system)
    private let status = UILabel()
    private var shift = false
    private var letterButtons: [UIButton] = []
    private let green = UIColor(red: 0.14, green: 0.34, blue: 0.25, alpha: 1)
    private var exchange: TranscriptExchange? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TranscriptExchange.appGroup)
            .map { TranscriptExchange(directory: $0.appendingPathComponent("Transcripts")) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 290)
        ])
        let top = UIStackView(); top.spacing = 10
        let brand = UILabel(); brand.text = "≋ wisprM"; brand.font = .boldSystemFont(ofSize: 17); brand.textColor = green
        top.addArrangedSubview(brand)
        let refresh = key("Refresh", action: #selector(refreshTranscript)); top.addArrangedSubview(refresh)
        stack.addArrangedSubview(top)
        insert.setTitle("Insert latest transcript", for: .normal); insert.backgroundColor = green
        insert.setTitleColor(.white, for: .normal); insert.layer.cornerRadius = 9
        insert.titleLabel?.font = .boldSystemFont(ofSize: 16); insert.heightAnchor.constraint(equalToConstant: 42).isActive = true
        insert.addTarget(self, action: #selector(insertTranscript), for: .touchUpInside)
        stack.addArrangedSubview(insert)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabel; status.numberOfLines = 2
        stack.addArrangedSubview(status)
        for letters in ["qwertyuiop", "asdfghjkl", "zxcvbnm"] {
            let row = UIStackView(); row.spacing = 4; row.distribution = .fillEqually
            for letter in letters {
                let button = key(String(letter), action: #selector(typeLetter(_:)))
                button.accessibilityIdentifier = String(letter); letterButtons.append(button); row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
        }
        let bottom = UIStackView(); bottom.spacing = 5; bottom.distribution = .fillProportionally
        for (title, selector) in [("⇧", #selector(toggleShift)), ("🌐", #selector(nextKeyboard)), ("Space", #selector(space)), (".", #selector(period)), ("⌫", #selector(backspace)), ("Return", #selector(newline))] {
            bottom.addArrangedSubview(key(title, action: selector))
        }
        stack.addArrangedSubview(bottom); refreshTranscript()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refreshTranscript() }
    private func key(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal)
        button.backgroundColor = .tertiarySystemBackground; button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 5; button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    @objc private func refreshTranscript() {
        do {
            latest = try exchange?.latest()
            if let latest, UserDefaults.standard.string(forKey: "last-inserted-id") != latest.id.uuidString {
                insert.isEnabled = true; insert.alpha = 1
                status.text = String(latest.text.prefix(100))
            } else {
                insert.isEnabled = false; insert.alpha = 0.45
                status.text = "Record in wisprM, then return here and tap Refresh. Shared text expires after 10 minutes."
            }
        } catch {
            latest = nil; insert.isEnabled = false; insert.alpha = 0.45
            status.text = "Shared text is unavailable. Open wisprM or paste from your clipboard."
        }
    }
    @objc private func insertTranscript() {
        // Read again at the moment of insertion; no delayed insertion into another document.
        refreshTranscript()
        guard insert.isEnabled, let latest else { return }
        textDocumentProxy.insertText(latest.text)
        UserDefaults.standard.set(latest.id.uuidString, forKey: "last-inserted-id")
        self.latest = nil; refreshTranscript()
    }
    @objc private func typeLetter(_ sender: UIButton) {
        guard let letter = sender.accessibilityIdentifier else { return }
        textDocumentProxy.insertText(shift ? letter.uppercased() : letter)
    }
    @objc private func toggleShift() {
        shift.toggle()
        for button in letterButtons { if let letter = button.accessibilityIdentifier { button.setTitle(shift ? letter.uppercased() : letter, for: .normal) } }
    }
    @objc private func nextKeyboard() { advanceToNextInputMode() }
    @objc private func space() { textDocumentProxy.insertText(" ") }
    @objc private func period() { textDocumentProxy.insertText(".") }
    @objc private func backspace() { textDocumentProxy.deleteBackward() }
    @objc private func newline() { textDocumentProxy.insertText("\n") }
}
