#!/usr/bin/env python

import os
import appdirs
import sys
import sqlite3
import json
from PyQt6.QtWidgets import *
from PyQt6.QtGui import *
from PyQt6.QtCore import *


class EntityBrowser(QMainWindow):
    def __init__(self, db_path):
        super().__init__()
        self.setWindowTitle("Entity Browser")

        # Database
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row

        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        self.layout = QHBoxLayout(central_widget)

        # Left: Types
        self.typeView = QListView()
        self.typeModel = QStringListModel()
        self.typeView.setModel(self.typeModel)
        self.layout.addWidget(self.typeView)

        # Middle: IDs
        self.idView = QListView()
        self.idModel = QStringListModel()
        self.idView.setModel(self.idModel)
        self.layout.addWidget(self.idView)

        # Right: JSON data
        right_layout = QVBoxLayout()
        self.dataView = QPlainTextEdit()
        self.dataView.setReadOnly(True)
        right_layout.addWidget(self.dataView)

        # Delete button
        self.deleteButton = QPushButton("Delete")
        self.deleteButton.clicked.connect(self.delete_selected_entity)
        right_layout.addWidget(self.deleteButton)

        # Wrap in a widget for right column
        right_widget = QWidget()
        right_widget.setLayout(right_layout)
        self.layout.addWidget(right_widget)

        # Status bar
        self.statusBar = QStatusBar()
        self.setStatusBar(self.statusBar)

        toolbar = QToolBar("Main Toolbar")
        self.addToolBar(toolbar)
        reload_action = QAction(QIcon.fromTheme("view-refresh"), "Reload", self)
        reload_action.setStatusTip("Reload all data from database")
        reload_action.triggered.connect(self.reload_all)
        toolbar.addAction(reload_action)

        # Total entity count
        self.total_entities = self.get_total_entity_count()

        # Connect selection signals
        self.typeView.selectionModel().currentChanged.connect(self.on_type_selected)
        self.idView.selectionModel().currentChanged.connect(self.on_id_selected)

        # Load types
        self.load_types()

    def reload_all(self):
        self.total_entities = self.get_total_entity_count()
        self.load_types()

    def delete_selected_entity(self):
        current_type_index = self.typeView.currentIndex()
        current_id_index = self.idView.currentIndex()

        selected_type = current_type_index.data()
        selected_id = current_id_index.data()

        if not selected_id:
            QMessageBox.warning(self, "No Selection", "No entity ID selected.")
            return

        reply = QMessageBox.question(
            self,
            "Confirm Deletion",
            f"Are you sure you want to delete entity ID {selected_id} of type '{selected_type}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:
            try:
                self.conn.execute("DELETE FROM entities WHERE id = ?", (selected_id,))
                self.conn.commit()
                self.statusBar.showMessage(f"Deleted entity ID {selected_id}.", 5000)
                self.total_entities = self.get_total_entity_count()
                self.on_type_selected(current_type_index, current_type_index)  # Refresh ID list
            except Exception as e:
                QMessageBox.critical(self, "Deletion Error", str(e))

    def get_total_entity_count(self):
        try:
            cursor = self.conn.execute("SELECT COUNT(*) FROM entities")
            count = cursor.fetchone()[0]
            return count
        except Exception as e:
            QMessageBox.critical(self, "Database Error", str(e))
            return 0

    def update_status_bar(self, type_count):
        self.statusBar.showMessage(
            f"Total entities: {self.total_entities} | Entities of selected type: {type_count}"
        )

    def load_types(self):
        try:
            cursor = self.conn.execute("SELECT DISTINCT type FROM entities ORDER BY type ASC")
            types = [row["type"] for row in cursor.fetchall()]
            self.typeModel.setStringList(types)

            # Auto-select first type
            if types:
                self.typeView.setCurrentIndex(self.typeModel.index(0))
        except Exception as e:
            QMessageBox.critical(self, "Database Error", str(e))

    def on_type_selected(self, current: QModelIndex, previous: QModelIndex):
        selected_type = current.data()
        try:
            cursor = self.conn.execute(
                "SELECT id FROM entities WHERE type = ? ORDER BY id ASC", (selected_type,)
            )
            ids = [str(row["id"]) for row in cursor.fetchall()]
            self.idModel.setStringList(ids)
            self.dataView.clear()

            # Auto-select first ID
            if ids:
                self.idView.setCurrentIndex(self.idModel.index(0))

            # Update status bar
            self.update_status_bar(len(ids))
        except Exception as e:
            QMessageBox.critical(self, "Database Error", str(e))

    def on_id_selected(self, current: QModelIndex, previous: QModelIndex):
        selected_id = current.data()
        if not selected_id:
            return
        try:
            cursor = self.conn.execute(
                "SELECT data FROM entities WHERE id = ?", (selected_id,)
            )
            row = cursor.fetchone()
            if row:
                try:
                    json_data = json.loads(row["data"])
                    pretty_json = json.dumps(json_data, indent=4)
                    self.dataView.setPlainText(pretty_json)
                except json.JSONDecodeError:
                    self.dataView.setPlainText("Invalid JSON data.")
        except Exception as e:
            QMessageBox.critical(self, "Error", str(e))

if __name__ == "__main__":
    app = QApplication(sys.argv)
    db_path = os.path.join(appdirs.user_data_dir('space'), 'space.db')
    window = EntityBrowser(db_path)
    window.resize(900, 500)
    window.show()
    sys.exit(app.exec())
