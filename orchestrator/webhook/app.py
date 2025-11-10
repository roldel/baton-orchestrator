from flask import Flask, request, abort

app = Flask(__name__)

# This route will now receive requests to /webhook/payload due to Nginx rewrite
@app.route('/webhook/payload', methods=['POST'])
def github_webhook():
    if request.method == 'POST':
        # Verify the signature
        # Process the payload
        print(request.json)
        return 'Webhook received!', 200
    abort(400)

@app.route('/health', methods=['GET'])
def health_check():
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)