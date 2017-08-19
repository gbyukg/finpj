import org.boon.Boon;
import groovy.io.FileType

def base_db_img_list = []
def base_db_imgs = ''
def dir = new File("/gsa/pokgsa/projects/s/salesconnectcn/db2backup")
dir.eachFileRecurse (FileType.FILES) { file ->
    base_db_img_list << file.getName()
}

base_db_imgs = base_db_img_list.join(", ")

def jsonEditorOptions = Boon.fromJson(/{
        disable_edit_json: true,
        disable_properties: true,
        disable_collapse: true,
        disable_array_add: true,
        disable_array_delete: true,
        disable_array_reorder: true,
        input_height: "60px",
        theme: "bootstrap2",
        iconlib:"fontawesome4",
        schema: {
            type: "object",
            title: "",
            properties: {
                source_from: {
                    title: "Chose SC source",
                    type: "array",
                    format: "tabs",
                    propertyOrder : 1,
                    items: {
                        title: "source",
                        headerTemplate: "{{self.name}}",
                        type: "object",
                        properties: {
                            name : {
                                type: "string",
                                title: "",
                                readOnly: "true",
                            },
                            GIT : {
                                title: "GIT PRs or branches",
                                type: "string",
                                format: "textarea",
                                input_height: "60px",
                            },
                            PACKAGE : {
                                title: "Install & upgrade packages",
                                type: "string",
                                format: "textarea",
                            }
                        }
                    }
                },
                install_method: {
                    title: "Chose install method",
                    type: "array",
                    format: "tabs",
                    propertyOrder : 2,
                    items: {
                        title: "",
                        headerTemplate: "{{self.name}}",
                        type: "object",
                        properties: {
                            name : {
                                type: "string",
                                title: "",
                                hidden: "true",
                                hiddenTitle: "true",
                                readOnly: "true",
                            },
                            BASE_DB : {
                                title: "Base DB",
                                description: "\nChoice which DB you want to use as a base DB, the process will create A new SC Instance base on your choice.",
                                type: "string",
                                enum: [' ', ${base_db_imgs}],
                                propertyOrder : 1,
                            },
                            RUN_DATALOADER: {
                                type: "boolean",
                                format: "checkbox",
                                title: "Import dataloader",
                                propertyOrder : 2,
                            },
                            RUN_AVL: {
                                type: "boolean",
                                format: "checkbox",
                                title: "Import AVLs",
                                propertyOrder : 3,
                            },
                            RUN_UNIT: {
                                type: "boolean",
                                format: "checkbox",
                                title: "Run PHP UT",
                                propertyOrder : 4,
                            },
                            AS_BASE_DB: {
                                type: "boolean",
                                format: "checkbox",
                                title: "As base DB img",
                                propertyOrder : 5,
                            },
                        }
                    }
                },
                KEEP_LIVE : {
                    type: "string",
                    format: "number",
                    title: "How log you want to keep the instance",
                    description: "1 ~ 30",
                    propertyOrder : 3
                },
                INSTALL_BP: {
                    type: "boolean",
                    format: "checkbox",
                    title: "Install SC4BP instance",
                    propertyOrder : 4
                },
                INDEPENDENT_ES: {
                    type: "boolean",
                    format: "checkbox",
                    title: 'Create a independent ES',
                    propertyOrder : 5
                },
                RUN_QRR: {
                    type: "boolean",
                    format: "checkbox",
                    title: 'Run QRR after installation',
                    propertyOrder : 6
                },
                INSTANCE_NAME: {
                    type: "string",
                    title: "Instance Name",
                    propertyOrder : 7
                },
                DB_NAME: {
                    type: "string",
                    title: "Instance DB Name",
                    propertyOrder : 8
                },
                ATOI_INSTALL_HOOK: {
                    type: "string",
                    title: "Custom instance Hooks",
                    propertyOrder : 9
                },
            }
        },

        startval: {
            KEEP_LIVE: 3,
            INSTALL_BP : 0,
            INDEPENDENT_ES : 0,
            INSTANCE_NAME : '',
            DB_NAME : "",
            RUN_QRR : '',
            ATOI_INSTALL_HOOK : '',
            source_from : [
                {
                    name: 'GIT',
                    GIT: ''
                },
                {
                    name: 'PACKAGE',
                    PACKAGE: ''
                }
            ],
            install_method: [
                {
                    name: 'RESTORE',
                    BASE_DB: '',
                    RUN_DATALOADER: '',
                    RUN_AVL: '',
                    RUN_UNIT: 1,
                },
                {
                    name: 'FULL_INSTALL',
                    RUN_DATALOADER: 1,
                    RUN_AVL: 1,
                    RUN_UNIT: 1,
                    AS_BASE_DB: 0,
                }
            ],
        }
}/);
