import json
import os
from bson import ObjectId
from pymongo import MongoClient

# Initialize MongoDB Client outside handler for reusability
client = MongoClient(os.environ["MONGO_URI"])
db = client["noticeboard_db"]
notices_col = db["notices"]


def JSONEncoder(data):
    """Utility to turn MongoDB ObjectIds into strings for JSON response."""
    if isinstance(data, list):
        for item in data:
            item["_id"] = str(item["_id"])
    elif isinstance(data, dict):
        data["_id"] = str(data["_id"])
    return data


def lambda_handler(event, context):
    http_method = event.get("requestContext", {}).get("http", {}).get("method")
    path_parameters = event.get("pathParameters") or {}
    notice_id = path_parameters.get("id")

    # Parse body for POST/PUT requests
    body = {}
    if event.get("body"):
        try:
            body = json.loads(event["body"])
        except Exception:
            pass

    response_body = {}
    status_code = 200

    try:
        # 1. READ ALL (GET /notices)
        if http_method == "GET" and not notice_id:
            notices = list(notices_col.find())
            response_body = JSONEncoder(notices)

        # 2. READ ONE (GET /notices/{id})
        elif http_method == "GET" and notice_id:
            notice = notices_col.find_one({"_id": ObjectId(notice_id)})
            if notice:
                response_body = JSONEncoder(notice)
            else:
                status_code = 404
                response_body = {"error": "Notice not found"}

        # 3. CREATE (POST /notices)
        elif http_method == "POST":
            new_notice = {
                "title": body.get("title", "Untitled"),
                "content": body.get("content", ""),
            }
            result = notices_col.insert_one(new_notice)
            new_notice["_id"] = str(result.inserted_id)
            status_code = 201
            response_body = new_notice

        # 4. UPDATE (PUT /notices/{id})
        elif http_method == "PUT" and notice_id:
            update_data = {}
            if "title" in body:
                update_data["title"] = body["title"]
            if "content" in body:
                update_data["content"] = body["content"]

            notices_col.update_one(
                {"_id": ObjectId(notice_id)}, {"$set": update_data}
            )
            response_body = {"message": "Notice updated successfully"}

        # 5. DELETE (DELETE /notices/{id})
        elif http_method == "DELETE" and notice_id:
            notices_col.delete_one({"_id": ObjectId(notice_id)})
            response_body = {"message": "Notice deleted successfully"}

        else:
            status_code = 400
            response_body = {"error": "Unsupported route"}

    except Exception as e:
        status_code = 500
        response_body = {"error": str(e)}

    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(response_body),
    }
