from __future__ import annotations
import firebase_admin
from firebase_admin import credentials, firestore
from typing import Optional

_app = None

def get_db():
    global _app
    if _app is None:
        try:
            _app = firebase_admin.initialize_app()
        except ValueError:
            # already initialized
            pass
    return firestore.client()
